# ==============================================================================
# wrapped.nix
#
# Module for creating wrapped versions of packages that inject secrets as
# environment variables at runtime.
#
# This module allows users to specify packages that should be wrapped with
# secrets from a specific app/environment. The wrapper script will:
# 1. Decrypt the combined secrets file for the app/environment
# 2. Export the secrets as environment variables
# 3. Execute the wrapped program
#
# Usage:
#   stackpanel.secrets.wrapped = {
#     enable = true;
#     projectRoot = ".";  # Path to project root (for finding secrets)
#
#     apps.myapp = {
#       packages = [ pkgs.nodejs pkgs.python3 ];
#       environments = [ "dev" "staging" "prod" ];
#     };
#   };
#
# Access wrapped packages via:
#   config.stackpanel.secrets.wrapped.packages.myapp.dev.nodejs
#   config.stackpanel.secrets.wrapped.packages.myapp.prod.python3
#
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

  # Convert age key files list to bash array string
  ageKeyLocationsArray = lib.concatMapStringsSep "\n      " (loc: ''"${loc}"'') cfg.age-key-files;

  # For inline use in wrapProgram (space-separated, no newlines)
  ageKeyLocationsInline = lib.concatMapStringsSep " " (loc: ''"${loc}"'') cfg.age-key-files;

  # Standard environments
  standardEnvs = [
    "dev"
    "staging"
    "prod"
  ];

  # Create the wrapper script that decrypts secrets and exports them
  mkSecretsLoaderScript = pkgs.writeShellApplication {
    name = "secrets-loader";
    runtimeInputs = [
      pkgs.age
      pkgs.yq-go
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      # Arguments: <secrets-file> <command> [args...]
      SECRETS_FILE="$1"
      shift

      # Check configured locations for AGE key file
      AGE_KEY_LOCATIONS=(
        ${ageKeyLocationsArray}
      )

      AGE_KEY_FILE=""
      for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
        [[ -z "$loc" ]] && continue
        if [[ -f "$loc" ]]; then
          AGE_KEY_FILE="$loc"
          break
        fi
      done

      if [[ -z "$AGE_KEY_FILE" ]]; then
        echo "Error: AGE key file not found in any of these locations:" >&2
        for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
          [[ -n "$loc" ]] && echo "  - $loc" >&2
        done
        echo "Set SOPS_AGE_KEY_FILE or create the key file." >&2
        exit 1
      fi

      if [[ ! -f "$SECRETS_FILE" ]]; then
        echo "Error: Secrets file not found: $SECRETS_FILE" >&2
        exit 1
      fi

      # Decrypt and export secrets as environment variables
      DECRYPTED=$(age -d -i "$AGE_KEY_FILE" "$SECRETS_FILE")

      # Parse YAML and export each key as an environment variable
      # Handle multiline values by trimming trailing newlines
      while IFS='=' read -r key value; do
        if [[ -n "$key" ]]; then
          # Trim trailing whitespace/newlines from value
          value="''${value%"''${value##*[![:space:]]}"}"
          export "$key=$value"
        fi
      done < <(echo "$DECRYPTED" | yq -o json | jq -r 'to_entries | .[] | "\(.key)=\(.value)"')

      # Execute the command with the exported environment
      exec "$@"
    '';
  };

  # Create a wrapped package for a specific app/environment
  # The wrapper will decrypt secrets at runtime and inject them as env vars
  mkWrappedPackage =
    {
      pkg,
      appName,
      envName,
      secretsDir,
    }:
    let
      # Path to the combined secrets file (relative to project root)
      secretsFile = "${secretsDir}/apps/${appName}/${envName}.yaml";

      # Derive package name safely
      pkgName = pkg.pname or pkg.name or "wrapped";
    in
    pkgs.symlinkJoin {
      name = "${pkgName}-${appName}-${envName}";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        # Find the secrets file path - use PROJECT_ROOT env var at runtime if set
        # Otherwise use the configured projectRoot as a relative path

        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              --run 'SECRETS_FILE="''${PROJECT_ROOT:-.}/${secretsFile}"' \
              --prefix PATH : "${mkSecretsLoaderScript}/bin" \
              --prefix PATH : "${pkgs.age}/bin" \
              --prefix PATH : "${pkgs.yq-go}/bin" \
              --prefix PATH : "${pkgs.jq}/bin" \
              --run '
                if [ -f "$SECRETS_FILE" ]; then
                  # Check configured locations for AGE key file
                  AGE_KEY_FILE=""
                  for loc in ${ageKeyLocationsInline}; do
                    [ -z "$loc" ] && continue
                    if [ -f "$loc" ]; then
                      AGE_KEY_FILE="$loc"
                      break
                    fi
                  done
                  if [ -n "$AGE_KEY_FILE" ]; then
                    DECRYPTED=$(age -d -i "$AGE_KEY_FILE" "$SECRETS_FILE" 2>/dev/null) || true
                    if [ -n "$DECRYPTED" ]; then
                      while IFS="=" read -r key value; do
                        if [ -n "$key" ]; then
                          value="''${value%"''${value##*[![:space:]]}"}"
                          export "$key=$value"
                        fi
                      done < <(echo "$DECRYPTED" | yq -o json | jq -r "to_entries | .[] | \"\\(.key)=\\(.value)\"")
                    fi
                  fi
                fi
              '
          fi
        done
      '';
    };

  # Generate all wrapped packages for all apps and environments
  # Structure: { appName.envName.pkgName = derivation }
  mkAllWrappedPackages =
    let
      secretsDir = cfg.input-directory;

      # For each app, generate wrapped packages for each environment
      mkAppPackages =
        appName: appCfg:
        let
          envs = appCfg.environments or standardEnvs;
          packages = appCfg.packages or [ ];

          # For each environment, wrap all packages
          mkEnvPackages =
            envName:
            lib.listToAttrs (
              map (pkg: {
                name = pkg.pname or pkg.name or "wrapped";
                value = mkWrappedPackage {
                  inherit
                    pkg
                    appName
                    envName
                    secretsDir
                    ;
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

  # Flatten all wrapped packages into a list for devshell
  flattenWrappedPackages =
    packages:
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
      description = ''
        Enable creation of wrapped packages that inject secrets as environment variables.
        When enabled, you can specify packages per app that will be wrapped with
        automatic secrets loading for each environment.
      '';
    };

    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = ".";
      description = ''
        Path to the project root directory. This is used to locate the secrets
        files at runtime. Can be overridden by setting PROJECT_ROOT environment
        variable when running the wrapped package.
      '';
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = ''
                List of packages to create wrapped versions of.
                Each package will have wrapped versions created for each environment.
              '';
            };

            environments = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = standardEnvs;
              description = ''
                List of environments to create wrapped packages for.
                Defaults to: dev, staging, prod
              '';
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          myapp = {
            packages = [ pkgs.nodejs pkgs.python3 ];
            environments = [ "dev" "staging" "prod" ];
          };
        }
      '';
      description = ''
        Per-app configuration for wrapped packages.
        Each app can specify which packages to wrap and for which environments.
      '';
    };

    packages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.package));
      default = mkAllWrappedPackages;
      readOnly = true;
      description = ''
        Generated wrapped packages, organized by app name, environment, and package name.
        Access like: config.stackpanel.secrets.wrapped.packages.<app>.<env>.<package>
      '';
    };

    addToDevshell = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to add all wrapped packages to the devshell.
        Usually you only want specific wrapped packages, so this defaults to false.
      '';
    };

    devshellEnvironment = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "dev";
      description = ''
        When addToDevshell is true, which environment's wrapped packages to add.
        Set to null to add all environments (not recommended).
      '';
    };
  };

  config = lib.mkIf (cfg.enable && wrappedCfg.enable) {
    # Expose the secrets loader script as a package
    stackpanel.secrets.packages.secrets-loader = mkSecretsLoaderScript;

    # Optionally add to devshell
    stackpanel.devshell.packages = lib.mkIf wrappedCfg.addToDevshell (
      if wrappedCfg.devshellEnvironment != null then
        # Add only packages for the specified environment
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
        # Add all wrapped packages
        flattenWrappedPackages mkAllWrappedPackages
    );

    # Add helper script to run any package with secrets from an app/env
    stackpanel.scripts = {
      "secrets:run" = {
        description = "Run a command with secrets loaded from an app environment (args: <app> <env> <command...>)";
        exec = ''
          if [[ $# -lt 3 ]]; then
            echo "Usage: secrets:run <app-name> <environment> <command> [args...]"
            echo ""
            echo "Runs a command with secrets from the specified app/environment loaded as env vars."
            echo ""
            echo "Example: secrets:run myapp dev node server.js"
            exit 1
          fi

          APP_NAME="$1"
          ENV_NAME="$2"
          shift 2

          PROJECT_ROOT="''${PROJECT_ROOT:-$(pwd)}"
          SECRETS_FILE="$PROJECT_ROOT/${cfg.input-directory}/apps/$APP_NAME/$ENV_NAME.yaml"

          exec ${mkSecretsLoaderScript}/bin/secrets-loader "$SECRETS_FILE" "$@"
        '';
      };
    };
  };
}
