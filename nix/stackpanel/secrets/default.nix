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
# - Team collaboration via recipients directory + GitHub Actions rekey workflow
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
#
# Team Onboarding:
#   On first shell entry, each developer's AGE public key is auto-registered in
#   .stackpanel/secrets/keys/recipients/<username>.pub (committed to git).
#   The keys/.sops.yaml is rebuilt from ALL recipients/*.pub files.
#
#   secrets:init-group uploads the group private key to GitHub as a secret and
#   generates a GitHub Actions workflow (.github/workflows/secrets-rekey.yml)
#   that triggers on pushes to recipients/*.pub. The workflow re-encrypts all
#   .enc.age files for all current recipients, enabling self-service onboarding.
#
#   Flags for secrets:init-group:
#     --no-gh          Skip GitHub integration entirely
#     --force-gh       Overwrite existing GitHub secret (use with care)
#     --no-ssm         Skip SSM storage
#     --dry-run        Preview without making changes
#     --json           Output structured JSON
#
# Key Integrity:
#   config.nix is the single source of truth for group public keys.
#   groups/.sops.yaml is GENERATED at shell entry from config.nix (gitignored).
#   A wrapped SOPS binary (named "sops") resolves the correct group public key
#   from Nix config at build time and injects --age per invocation, plus sets
#   SOPS_AGE_KEY_CMD for private key resolution. This eliminates key drift
#   between config files.
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

  # Import cfg.nix for path resolution in shell hooks
  cfgLib = import ../lib/cfg.nix { inherit lib; };

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
    "key-cmd" = orNull "" group.key-cmd;
    ref = group.computed-ref;
  }) cfg.groups;

  # Build the list of group key resolution blocks for the sops-age-keys script.
  # For each group, tries (in order):
  #   1. All .age files in keys/ (plain private keys, gitignored)
  #   2. Per-group key-cmd fallback (default: sops --decrypt .enc.age)
  #
  # Reading ALL .age files means old/rotated keys are automatically available
  # for decrypting secrets still encrypted to them, without any re-keying.
  allAgeFilesBlock = ''
    # Read ALL .age files in the keys directory (includes current + rotated keys)
     KEYS_DIR="${cfg.secrets-dir}/keys"
    if [[ -d "$KEYS_DIR" ]]; then
      for age_file in "$KEYS_DIR"/*.age; do
        [[ -f "$age_file" ]] || continue
        while IFS= read -r line; do
          if [[ "$line" =~ AGE-SECRET-KEY- ]]; then
            echo "$line"
          fi
        done < "$age_file"
      done
    fi
  '';

  # Per-group key-cmd fallback (for .enc.age decryption when no plain .age exists)
  groupKeyBlocks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: group:
      let
        keyCmd = orNull "" group.key-cmd;
      in
      lib.optionalString (keyCmd != "") ''
        # Group: ${name} — key-cmd fallback
        GROUP_OUTPUT=$(${keyCmd} 2>/dev/null) || true
        if [[ -n "$GROUP_OUTPUT" ]]; then
          while IFS= read -r line; do
            if [[ "$line" =~ AGE-SECRET-KEY- ]]; then
              echo "$line"
            fi
          done <<< "$GROUP_OUTPUT"
        fi
      ''
    ) cfg.groups
  );

  # ═══════════════════════════════════════════════════════════════════════════
  # sops-age-keys: SOPS_AGE_KEY_CMD script
  #
  # Outputs all available AGE private keys to stdout, one per line.
  # Called lazily by SOPS when it needs to decrypt.
  #
  # Key sources:
  #   1. Local AGE key (always, from .stackpanel/state/keys/local.txt)
  #   2. Per-group key-cmd (configurable, default: sops --decrypt .enc.age)
  # ═══════════════════════════════════════════════════════════════════════════
  sops-age-keys = pkgs.writeShellApplication {
    name = "sops-age-keys";
    runtimeInputs = [
      pkgs.sops
    ];
    text = ''
      ${cfgLib.bashLib}

      # Prevent recursive invocation: SOPS_AGE_KEY_CMD calls this script,
      # and group key-cmds may call sops, which would call this script again.
      # Break the cycle by unsetting SOPS_AGE_KEY_CMD and using SOPS_AGE_KEY
      # for any inner sops calls.
      unset SOPS_AGE_KEY_CMD

      LOCAL_KEY_FILE=${cfgLib.getKnown "paths.local-key"}

      # Step 1: Local AGE key (always available)
      if [[ -f "$LOCAL_KEY_FILE" ]]; then
        LOCAL_KEY=$(grep "^AGE-SECRET-KEY-" "$LOCAL_KEY_FILE" 2>/dev/null || true)
        if [[ -n "$LOCAL_KEY" ]]; then
          echo "$LOCAL_KEY"
          # Set SOPS_AGE_KEY so inner sops calls (from group key-cmds) can decrypt
          export SOPS_AGE_KEY="$LOCAL_KEY"
        fi
      fi

      # Step 2: All .age files in keys/ (current + rotated group keys)
      ${allAgeFilesBlock}

      # Step 3: Per-group key-cmd fallback (.enc.age decryption)
      ${groupKeyBlocks}
    '';
  };

  # ═══════════════════════════════════════════════════════════════════════════
  # Packages
  # ═══════════════════════════════════════════════════════════════════════════

  # Wrapped SOPS that resolves group→pubkey from Nix config and passes --age
  # per invocation. Also sets SOPS_AGE_KEY_CMD for private key resolution.
  # This ensures encryption always uses the canonical key from config.nix.
  sops-wrapped = pkgs.writeShellApplication {
    name = "sops";
    runtimeInputs = [
      pkgs.jq
    ];
    text = secretsLib.sopsWrappedScript {
      inherit groupsConfig;
      sopsAgeKeysPath = "${sops-age-keys}/bin/sops-age-keys";
    };
  };

  secrets-set = pkgs.writeShellApplication {
    name = "secrets-set";
    runtimeInputs = [
      sops-wrapped
    ];
    text = secretsLib.setSecretScript;
  };

  secrets-get = pkgs.writeShellApplication {
    name = "secrets-get";
    runtimeInputs = [
      sops-wrapped
      pkgs.yq-go
    ];
    text = secretsLib.getSecretScript;
  };

  secrets-list = pkgs.writeShellApplication {
    name = "secrets-list";
    runtimeInputs = [
      sops-wrapped
      pkgs.yq-go
    ];
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
      pkgs.sops
      pkgs.gh
      pkgs.gawk
    ];
    # NOTE: awscli2 is not a hard dependency - SSM storage is optional.
    # If aws CLI is in PATH, it will be used. Otherwise SSM is skipped.
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
      sops-wrapped # wrapped sops that resolves keys from Nix config
      sops-age-keys
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

    # Auto-generate local master key and SOPS configs on shell entry
    stackpanel.devshell.hooks.before = [
      ''
        (
        ${secretsLib.autoGenerateLocalKeyScript}
        )
      ''
      ''
        (
        ${secretsLib.generateGroupsSopsConfigScript { inherit groupsConfig; }}
        )
      ''
    ];

    # ═══════════════════════════════════════════════════════════════════════════
    # Scripts
    # ═══════════════════════════════════════════════════════════════════════════

    stackpanel.scripts = {
      "secrets:set" = {
        exec = "${secrets-set}/bin/secrets-set \"$@\"";
        description = "Set a secret value in a SOPS group file";
        args = [
          {
            name = "key";
            description = "Secret key name (e.g., API_KEY, DATABASE_URL)";
            required = true;
          }
          {
            name = "--group";
            description = "Target group (dev, prod, staging, etc.)";
            default = "dev";
          }
          {
            name = "--value";
            description = "The secret value (reads from stdin if not provided)";
          }
        ];
      };

      "secrets:get" = {
        exec = "${secrets-get}/bin/secrets-get \"$@\"";
        description = "Get a decrypted secret value from a SOPS group file";
        args = [
          {
            name = "key";
            description = "Secret key name (e.g., API_KEY, DATABASE_URL)";
            required = true;
          }
          {
            name = "--group";
            description = "Source group (dev, prod, staging, etc.)";
            default = "dev";
          }
        ];
      };

      "secrets:list" = {
        exec = "${secrets-list}/bin/secrets-list \"$@\"";
        description = "List all secrets across SOPS group files";
        args = [
          {
            name = "group";
            description = "Optional: filter to a specific group";
          }
        ];
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
        # ================================================================
        # SOPS AGE key command
        #
        # Instead of eagerly loading all keys at shell entry, we set
        # SOPS_AGE_KEY_CMD to a script that lazily retrieves keys on demand.
        # This avoids slow AWS/SSM calls on every shell entry and supports
        # pluggable key backends via the group key-cmd option.
        # ================================================================
        export SOPS_AGE_KEY_CMD="${sops-age-keys}/bin/sops-age-keys"
      ''
    ];

    stackpanel.files.entries.".gitignore".lines = [
      ".stackpanel/secrets/*.age"
      "!*.stackpanel/secrets/*.enc.age"
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
        keyCmd = orNull "" group.key-cmd;
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
