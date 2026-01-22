# ==============================================================================
# wrapped.nix
#
# Module for creating wrapped versions of packages that inject secrets as
# environment variables at runtime.
#
# This module allows users to specify packages that should be wrapped with
# secrets from a specific app/environment. The wrapper script will:
# 1. Resolve master keys and decrypt secrets
# 2. Export the secrets as environment variables
# 3. Execute the wrapped program
#
# Usage:
#   stackpanel.secrets.wrapped = {
#     enable = true;
#     apps.myapp = {
#       packages = [ pkgs.nodejs pkgs.python3 ];
#       environments = [ "dev" "staging" "prod" ];
#     };
#   };
#
# Access wrapped packages via:
#   config.stackpanel.secrets.wrapped.packages.myapp.dev.nodejs
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.secrets;
  wrappedCfg = cfg.wrapped;

  # Import secrets library
  secretsLib = import ./lib.nix {
    inherit pkgs lib;
    secretsDir = cfg.secrets-dir;
  };

  # Convert master-keys to JSON for shell scripts
  masterKeysConfig = lib.mapAttrs (name: key: {
    inherit (key) age-pub ref;
    "resolve-cmd" = key.resolve-cmd or null;
  }) cfg.master-keys;

  masterKeysJson = builtins.toJSON masterKeysConfig;

  # Standard environments
  standardEnvs = [ "dev" "staging" "prod" ];

  # Create the wrapper script that decrypts secrets using master keys
  mkSecretsLoaderScript = pkgs.writeShellApplication {
    name = "secrets-loader";
    runtimeInputs = [
      pkgs.age
      pkgs.vals
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      ${secretsLib.resolveMasterKeyScript}

      # Arguments: <secrets-file> <command> [args...]
      SECRETS_FILE="$1"
      shift

      MASTER_KEYS_JSON='${masterKeysJson}'

      if [[ ! -f "$SECRETS_FILE" ]]; then
        echo "Error: Secrets file not found: $SECRETS_FILE" >&2
        exit 1
      fi

      # Try each master key to decrypt
      DECRYPTED=""
      for KEY_NAME in $(echo "$MASTER_KEYS_JSON" | jq -r 'keys[]'); do
        REF=$(echo "$MASTER_KEYS_JSON" | jq -r --arg k "$KEY_NAME" '.[$k].ref')
        RESOLVE_CMD=$(echo "$MASTER_KEYS_JSON" | jq -r --arg k "$KEY_NAME" '.[$k]["resolve-cmd"] // ""')

        PRIVATE_KEY=$(resolve_master_key "$KEY_NAME" "$REF" "$RESOLVE_CMD" 2>/dev/null) || continue

        if [[ -n "$PRIVATE_KEY" ]]; then
          if DECRYPTED=$(echo "$PRIVATE_KEY" | age -d -i - "$SECRETS_FILE" 2>/dev/null); then
            break
          fi
        fi
      done

      if [[ -z "$DECRYPTED" ]]; then
        echo "Error: Could not decrypt secrets file with any master key" >&2
        exit 1
      fi

      # Parse decrypted content and export as environment variables
      while IFS='=' read -r key value; do
        if [[ -n "$key" ]]; then
          value="''${value%"''${value##*[![:space:]]}"}"
          export "$key=$value"
        fi
      done < <(echo "$DECRYPTED")

      # Execute the command with the exported environment
      exec "$@"
    '';
  };

  # Create a wrapped package for a specific app/environment
  mkWrappedPackage = { pkg, appName, envName, secretsDir }:
    let
      secretsFile = "${secretsDir}/apps/${appName}/${envName}.age";
      pkgName = pkg.pname or pkg.name or "wrapped";
    in
    pkgs.symlinkJoin {
      name = "${pkgName}-${appName}-${envName}";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              --set STACKPANEL_SECRETS_FILE "''${PROJECT_ROOT:-.}/${secretsFile}" \
              --prefix PATH : "${mkSecretsLoaderScript}/bin" \
              --prefix PATH : "${pkgs.age}/bin" \
              --prefix PATH : "${pkgs.vals}/bin" \
              --prefix PATH : "${pkgs.jq}/bin"
          fi
        done
      '';
    };

  # Generate all wrapped packages
  mkAllWrappedPackages =
    let
      secretsDir = cfg.secrets-dir;

      mkAppPackages = appName: appCfg:
        let
          envs = appCfg.environments or standardEnvs;
          packages = appCfg.packages or [ ];

          mkEnvPackages = envName:
            lib.listToAttrs (
              map (pkg: {
                name = pkg.pname or pkg.name or "wrapped";
                value = mkWrappedPackage {
                  inherit pkg appName envName secretsDir;
                };
              }) packages
            );
        in
        lib.listToAttrs (
          map (envName: {
            name = envName;
            value = mkEnvPackages envName;
          }) envs
        );
    in
    lib.mapAttrs mkAppPackages wrappedCfg.apps;

  flattenWrappedPackages = packages:
    lib.flatten (
      lib.mapAttrsToList (
        appName: envPkgs: lib.mapAttrsToList (envName: pkgSet: lib.attrValues pkgSet) envPkgs
      ) packages
    );

in
{
  options.stackpanel.secrets.wrapped = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable creation of wrapped packages that inject secrets.";
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "List of packages to wrap with secrets.";
            };

            environments = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = standardEnvs;
              description = "Environments to create wrapped packages for.";
            };
          };
        }
      );
      default = { };
      description = "Per-app configuration for wrapped packages.";
    };

    packages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.package));
      default = mkAllWrappedPackages;
      readOnly = true;
      description = "Generated wrapped packages: <app>.<env>.<package>";
    };

    addToDevshell = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add wrapped packages to the devshell.";
    };

    devshellEnvironment = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "dev";
      description = "Which environment's wrapped packages to add to devshell.";
    };
  };

  config = lib.mkIf (cfg.enable && wrappedCfg.enable) {
    stackpanel.devshell.packages = lib.mkIf wrappedCfg.addToDevshell (
      if wrappedCfg.devshellEnvironment != null then
        lib.flatten (
          lib.mapAttrsToList (
            appName: envPkgs:
            if envPkgs ? ${wrappedCfg.devshellEnvironment} then
              lib.attrValues envPkgs.${wrappedCfg.devshellEnvironment}
            else
              [ ]
          ) mkAllWrappedPackages
        )
      else
        flattenWrappedPackages mkAllWrappedPackages
    );

    stackpanel.scripts = {
      "secrets:run" = {
        description = "Run a command with secrets loaded (args: <app> <env> <command...>)";
        exec = ''
          if [[ $# -lt 3 ]]; then
            echo "Usage: secrets:run <app-name> <environment> <command> [args...]"
            exit 1
          fi

          APP_NAME="$1"
          ENV_NAME="$2"
          shift 2

          PROJECT_ROOT="''${PROJECT_ROOT:-$(pwd)}"
          SECRETS_FILE="$PROJECT_ROOT/${cfg.secrets-dir}/apps/$APP_NAME/$ENV_NAME.age"

          exec ${mkSecretsLoaderScript}/bin/secrets-loader "$SECRETS_FILE" "$@"
        '';
      };
    };
  };
}
