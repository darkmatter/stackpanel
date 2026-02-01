# ==============================================================================
# default.nix
#
# Master key-based secrets module.
#
# This module provides secrets management where:
# - A few master keys encrypt all secrets
# - Each secret (variable with type=SECRET) specifies which master keys can decrypt it
# - A default "local" key is auto-generated, ensuring secrets always work
# - Groups provide access control via externally-stored AGE keypairs
#
# Usage:
#   stackpanel.secrets.master-keys = {
#     local = { ... };  # auto-configured
#   };
#
#   # Groups auto-create master-key entries when initialized
#   stackpanel.secrets.groups = {
#     dev = { age-pub = "age1..."; };   # set after secrets:init-group dev
#     prod = { age-pub = "age1..."; };  # set after secrets:init-group prod
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
  variablesBackend = config.stackpanel.secrets.backend;
  isChamber = variablesBackend == "chamber";
  chamberCfg = config.stackpanel.secrets.chamber;
  chamberPrefix = chamberCfg.service-prefix;

  # Import secrets library
  secretsLib = import ./lib.nix {
    inherit pkgs lib;
    secretsDir = cfg.secrets-dir;
  };

  # Helper: coerce null to a default value (proto optional fields default to null,
  # and Nix's `a.b or default` only handles missing attrs, not null values)
  orNull = default: val: if val == null then default else val;

  # Convert master-keys to the format expected by lib scripts
  masterKeysConfig = lib.mapAttrs (name: key: {
    inherit (key) age-pub ref;
    "resolve-cmd" = key.resolve-cmd;
  }) cfg.master-keys;

  # Convert groups to the format expected by lib scripts
  groupsConfig = lib.mapAttrs (name: group: {
    "age-pub" = orNull "" group.age-pub;
    "ssm-path" = group.ssm-path;
    ref = group.computed-ref;
  }) cfg.groups;

  # ═══════════════════════════════════════════════════════════════════════════
  # Packages
  # ═══════════════════════════════════════════════════════════════════════════

  secrets-set = pkgs.writeShellApplication {
    name = "secrets-set";
    runtimeInputs = [
      pkgs.age
      pkgs.jq
    ];
    text = secretsLib.setSecretScript { inherit masterKeysConfig; };
  };

  secrets-get = pkgs.writeShellApplication {
    name = "secrets-get";
    runtimeInputs = [
      pkgs.age
      pkgs.jq
      pkgs.vals
    ];
    text = secretsLib.getSecretScript { inherit masterKeysConfig; };
  };

  secrets-list = pkgs.writeShellApplication {
    name = "secrets-list";
    text = secretsLib.listSecretsScript;
  };

  secrets-rekey = pkgs.writeShellApplication {
    name = "secrets-rekey";
    runtimeInputs = [
      pkgs.age
      pkgs.jq
      pkgs.vals
    ];
    text = secretsLib.rekeySecretScript { inherit masterKeysConfig; };
  };

  secrets-init-group = pkgs.writeShellApplication {
    name = "secrets-init-group";
    runtimeInputs = [
      pkgs.age
      pkgs.jq
      pkgs.awscli2
    ];
    text = secretsLib.initGroupScript {
      inherit groupsConfig chamberPrefix;
    };
  };

in
{
  config = lib.mkIf cfg.enable {
    # ═══════════════════════════════════════════════════════════════════════════
    # Devshell Integration
    # ═══════════════════════════════════════════════════════════════════════════

    # Add required packages to devshell
    # NOTE: secrets-init-group (and other script binaries) must be in packages
    # so they're available via the agent's exec API (which has PATH but not
    # devshell script functions).
    stackpanel.devshell.packages = [
      pkgs.age
      pkgs.vals
      pkgs.jq
      secrets-init-group
      secrets-set
      secrets-get
      secrets-list
      secrets-rekey
    ]
    ++ lib.optional isChamber pkgs.chamber;

    # Set CHAMBER_KMS_KEY_ALIAS when chamber backend is active.
    # This tells chamber which KMS key to use for encrypting SSM parameters.
    # The alias is derived from the infra aws-secrets KMS config if available,
    # otherwise falls back to the project name.
    stackpanel.devshell.env = lib.optionalAttrs isChamber {
      CHAMBER_KMS_KEY_ALIAS = "alias/${config.stackpanel.name or "my-project"}-secrets";
    };

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
        args = [
          {
            name = "variable-id";
            description = "Secret identifier (e.g., /prod/api-key)";
            required = true;
          }
          {
            name = "--keys";
            description = "Comma-separated list of master key names";
            default = "local";
          }
          {
            name = "--value";
            description = "The secret value (reads from stdin if not provided)";
          }
        ];
      };

      "secrets:get" = {
        exec = "${secrets-get}/bin/secrets-get \"$@\"";
        description = "Get a decrypted secret value";
        args = [
          {
            name = "variable-id";
            description = "Secret identifier (e.g., /prod/api-key)";
            required = true;
          }
        ];
      };

      "secrets:list" = {
        exec = "${secrets-list}/bin/secrets-list";
        description = "List all encrypted secrets";
      };

      "secrets:rekey" = {
        exec = "${secrets-rekey}/bin/secrets-rekey \"$@\"";
        description = "Re-encrypt a secret to different master keys";
        args = [
          {
            name = "variable-id";
            description = "Secret identifier to re-key";
            required = true;
          }
          {
            name = "--keys";
            description = "Comma-separated list of master key names to encrypt to";
            required = true;
          }
        ];
      };

      "secrets:init-group" = {
        exec = "${secrets-init-group}/bin/secrets-init-group \"$@\"";
        description = "Initialize a secrets group (generate AGE keypair, store in SSM)";
        args = [
          {
            name = "group-name";
            description = "Name of the secrets group to initialize";
            required = true;
          }
          {
            name = "--ssm-path";
            description = "Override the SSM path for storing the private key";
          }
          {
            name = "--dry-run";
            description = "Show what would happen without writing to SSM";
          }
          {
            name = "--yes";
            description = "Skip confirmation prompt";
          }
          {
            name = "--json";
            description = "Output results as JSON";
          }
        ];
      };

      "secrets:show-keys" = {
        exec = ''
          echo "Master Keys:"
          echo ""
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: key: ''
              echo "  ${name}:"
              echo "    public: ${key.age-pub}"
              echo "    ref: ${key.ref}"
              ${lib.optionalString (key.resolve-cmd != null) ''echo "    resolve-cmd: ${key.resolve-cmd}"''}
            '') cfg.master-keys
          )}

          echo ""
          echo "Groups:"
          echo ""
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              name: group:
              let
                pub = orNull "" group.age-pub;
              in
              ''
                echo "  ${name}:"
                echo "    public: ${if pub != "" then pub else "(not initialized)"}"
                echo "    ssm-path: ${group.ssm-path}"
                echo "    ref: ${group.computed-ref}"
                ${
                  if pub != "" then
                    ''echo "    status: initialized"''
                  else
                    ''echo "    status: pending (run: secrets:init-group ${name})"''
                }
              ''
            ) cfg.groups
          )}
        '';
        description = "Show configured master keys and groups";
      };
    };

    stackpanel.devshell.hooks.main = [
      ''
        # Load AGE master key from SSM for SOPS decryption
        if command -v aws &>/dev/null && command -v vals &>/dev/null; then
          # Add 3s timeout to prevent shell hang on expired AWS credentials
          if timeout 3 aws sts get-caller-identity &>/dev/null 2>&1; then
            AGE_KEY=$(vals eval "ref+awsssm:///stackpanel/keys/dev" 2>/dev/null || true)
            if [[ -n "$AGE_KEY" ]] && [[ "$AGE_KEY" =~ ^AGE-SECRET-KEY- ]]; then
              export SOPS_AGE_KEY="$AGE_KEY"
              echo "✓ Loaded AGE master key from SSM"
            fi
          fi
        fi
      ''
    ];


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
      groups = lib.mapAttrs (name: group: {
        agePub = orNull "" group.age-pub;
        ssmPath = group.ssm-path;
        ref = group.computed-ref;
      }) cfg.groups;
    };

    # Variables backend configuration for CLI/agent
    stackpanel.serializable.variables = {
      backend = variablesBackend;
    }
    // lib.optionalAttrs isChamber {
      chamber = {
        servicePrefix = chamberCfg.service-prefix;
      };
    };
  };
}
