# ==============================================================================
# default.nix
#
# Master key-based secrets module.
#
# This module provides secrets management where:
# - A few master keys encrypt all secrets
# - Each secret (variable with type=SECRET) specifies which master keys can decrypt it
# - A default "local" key is auto-generated, ensuring secrets always work
#
# Usage:
#   stackpanel.secrets.master-keys = {
#     local = { ... };  # auto-configured
#     dev = { age-pub = "age1..."; ref = "ref+awsssm://..."; };
#     prod = { age-pub = "age1..."; ref = "ref+awsssm://..."; };
#   };
#
#   stackpanel.variables."/prod/api-key" = {
#     type = "SECRET";
#     key = "API_KEY";
#     master-keys = [ "prod" ];
#   };
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.secrets;

  # Import secrets library
  secretsLib = import ./lib.nix {
    inherit pkgs lib;
    secretsDir = cfg.secrets-dir;
  };

  # Convert master-keys to the format expected by lib scripts
  masterKeysConfig = lib.mapAttrs (name: key: {
    inherit (key) age-pub ref;
    "resolve-cmd" = key.resolve-cmd or null;
  }) cfg.master-keys;

  # ═══════════════════════════════════════════════════════════════════════════
  # Packages
  # ═══════════════════════════════════════════════════════════════════════════

  secrets-set = pkgs.writeShellApplication {
    name = "secrets-set";
    runtimeInputs = [ pkgs.age pkgs.jq ];
    text = secretsLib.setSecretScript { inherit masterKeysConfig; };
  };

  secrets-get = pkgs.writeShellApplication {
    name = "secrets-get";
    runtimeInputs = [ pkgs.age pkgs.jq pkgs.vals ];
    text = secretsLib.getSecretScript { inherit masterKeysConfig; };
  };

  secrets-list = pkgs.writeShellApplication {
    name = "secrets-list";
    text = secretsLib.listSecretsScript;
  };

  secrets-rekey = pkgs.writeShellApplication {
    name = "secrets-rekey";
    runtimeInputs = [ pkgs.age pkgs.jq pkgs.vals ];
    text = secretsLib.rekeySecretScript { inherit masterKeysConfig; };
  };

in
{
  config = lib.mkIf cfg.enable {
    # ═══════════════════════════════════════════════════════════════════════════
    # Devshell Integration
    # ═══════════════════════════════════════════════════════════════════════════

    # Add required packages to devshell
    stackpanel.devshell.packages = [
      pkgs.age
      pkgs.vals
      pkgs.jq
    ];

    # Auto-generate local master key on shell entry
    stackpanel.devshell.hooks.before = [
      ''
        (
        ${secretsLib.autoGenerateLocalKeyScript}
        )
      ''
    ];

    # ═══════════════════════════════════════════════════════════════════════════
    # Scripts
    # ═══════════════════════════════════════════════════════════════════════════

    stackpanel.scripts = {
      "secrets:set" = {
        exec = "${secrets-set}/bin/secrets-set \"$@\"";
        description = "Set a secret value (encrypt to master keys)";
      };

      "secrets:get" = {
        exec = "${secrets-get}/bin/secrets-get \"$@\"";
        description = "Get a decrypted secret value";
      };

      "secrets:list" = {
        exec = "${secrets-list}/bin/secrets-list";
        description = "List all encrypted secrets";
      };

      "secrets:rekey" = {
        exec = "${secrets-rekey}/bin/secrets-rekey \"$@\"";
        description = "Re-encrypt a secret to different master keys";
      };

      "secrets:show-keys" = {
        exec = ''
          echo "Master Keys:"
          echo ""
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: key: ''
            echo "  ${name}:"
            echo "    public: ${key.age-pub}"
            echo "    ref: ${key.ref}"
            ${lib.optionalString (key.resolve-cmd != null) ''echo "    resolve-cmd: ${key.resolve-cmd}"''}
          '') cfg.master-keys)}
        '';
        description = "Show configured master keys";
      };
    };

    # ═══════════════════════════════════════════════════════════════════════════
    # Serializable config for CLI/agent
    # ═══════════════════════════════════════════════════════════════════════════

    stackpanel.serializable.secrets = {
      enable = cfg.enable;
      secretsDir = cfg.secrets-dir;
      masterKeys = lib.mapAttrs (name: key: {
        agePub = key.age-pub;
        ref = key.ref;
        resolveCmd = key.resolve-cmd;
      }) cfg.master-keys;
    };
  };
}
