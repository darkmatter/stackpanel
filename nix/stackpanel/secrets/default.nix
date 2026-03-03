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
#   .stackpanel/secrets/recipients/<username>.age.pub (committed to git).
#   The recipients/.sops.yaml is rebuilt from ALL recipients/**/*.age.pub files.
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
#   vars/.sops.yaml is GENERATED at shell entry from config.nix (gitignored).
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
  #   1. All .age files in recipients/ (plain private keys, gitignored)
  #   2. Archived keys in recipients/.archive/ (rotated keys)
  #   3. .vals files (optional, via `vals eval`)
  #   4. Per-group key-cmd fallback (default: sops --decrypt .enc.age)
  #
  # Reading ALL .age files means old/rotated keys are automatically available
  # for decrypting secrets still encrypted to them, without any re-keying.
  allAgeFilesBlock = ''
    # Read ALL .age private key files in the recipients directory (current keys)
    RECIPIENTS_DIR="${cfg.secrets-dir}/recipients"
    if [[ -d "$RECIPIENTS_DIR" ]]; then
      for age_file in "$RECIPIENTS_DIR"/*.age; do
        [[ -f "$age_file" ]] || continue
        # Skip .age.pub files (public keys) and .enc.age files (encrypted)
        [[ "$age_file" == *.age.pub ]] && continue
        [[ "$age_file" == *.enc.age ]] && continue
        while IFS= read -r line; do
          if [[ "$line" =~ AGE-SECRET-KEY- ]]; then
            echo "$line"
          fi
        done < "$age_file"
      done
      # Also read archived/rotated keys
      if [[ -d "$RECIPIENTS_DIR/.archive" ]]; then
        for age_file in "$RECIPIENTS_DIR/.archive"/*.age; do
          [[ -f "$age_file" ]] || continue
          while IFS= read -r line; do
            if [[ "$line" =~ AGE-SECRET-KEY- ]]; then
              echo "$line"
            fi
          done < "$age_file"
        done
      fi
    fi
  '';

  # .vals file resolution: for each <group>.vals file in recipients/,
  # read the vals reference and resolve it to an AGE private key.
  # This replaces per-value ref+sops:// with a single reference per group.
  valsFileBlock = ''
    # Check for .vals files in recipients/ (optional, needs vals)
    if [[ -d "$RECIPIENTS_DIR" ]]; then
      for vals_file in "$RECIPIENTS_DIR"/*.vals; do
        [[ -f "$vals_file" ]] || continue
        VALS_REF=$(cat "$vals_file" | tr -d '[:space:]')
        if [[ -n "$VALS_REF" ]] && command -v vals &>/dev/null; then
          VALS_OUTPUT=$(vals eval "$VALS_REF" 2>/dev/null) || true
          if [[ -n "$VALS_OUTPUT" ]]; then
            while IFS= read -r line; do
              if [[ "$line" =~ AGE-SECRET-KEY- ]]; then
                echo "$line"
              fi
            done <<< "$VALS_OUTPUT"
          fi
        fi
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
  # Key sources (in order):
  #   1. Local AGE key (always, from .stackpanel/state/keys/local.txt)
  #   2. Plaintext .age files in recipients/ (current + rotated group keys)
  #   3. .vals files in recipients/ (optional, via vals eval)
  #   4. Per-group key-cmd fallback (configurable, default: sops --decrypt .enc.age)
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

      # Step 2: All .age files in recipients/ (current + rotated group keys)
      ${allAgeFilesBlock}

      # Step 3: .vals files in recipients/ (optional, via vals eval)
      ${valsFileBlock}

      # Step 4: Per-group key-cmd fallback (.enc.age decryption)
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

  # secrets:load - Decrypt a SOPS vars file to dotenv format
  secrets-load = pkgs.writeShellApplication {
    name = "secrets-load";
    runtimeInputs = [
      sops-wrapped
    ];
    text = ''
      ${cfgLib.bashLib}

      SECRETS_DIR=${cfgLib.getWithDefault "secrets.secrets-dir" cfg.secrets-dir}
      VARS_DIR="$SECRETS_DIR/vars"

      usage() {
        echo "Usage: secrets:load <group> [--format dotenv|json|yaml]"
        echo ""
        echo "Decrypt a SOPS vars file and output in the specified format."
        echo ""
        echo "Options:"
        echo "  --format   Output format: dotenv (default), json, yaml"
        echo ""
        echo "Examples:"
        echo "  secrets:load dev"
        echo "  secrets:load common --format json"
        echo "  eval \$(secrets:load dev)   # load into current shell"
        exit 1
      }

      [[ $# -lt 1 ]] && usage

      GROUP="$1"
      shift
      FORMAT="dotenv"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --format|-f)
            FORMAT="$2"
            shift 2
            ;;
          -h|--help)
            usage
            ;;
          *)
            echo "Unknown option: $1" >&2
            usage
            ;;
        esac
      done

      GROUP_FILE="$VARS_DIR/$GROUP.sops.yaml"

      if [[ ! -f "$GROUP_FILE" ]]; then
        echo "Error: Group file not found: $GROUP_FILE" >&2
        echo "Available groups:" >&2
        for f in "$VARS_DIR"/*.sops.yaml; do
          [[ -f "$f" ]] && echo "  $(basename "$f" .sops.yaml)" >&2
        done
        exit 1
      fi

      case "$FORMAT" in
        dotenv)
          sops decrypt --output-type dotenv "$GROUP_FILE"
          ;;
        json)
          sops decrypt --output-type json "$GROUP_FILE"
          ;;
        yaml)
          sops decrypt "$GROUP_FILE"
          ;;
        *)
          echo "Error: Unknown format: $FORMAT (expected dotenv, json, or yaml)" >&2
          exit 1
          ;;
      esac
    '';
  };

  # secrets:join - Add local key to a recipient group
  secrets-join = pkgs.writeShellApplication {
    name = "secrets-join";
    runtimeInputs = [
      pkgs.age
      pkgs.git
    ];
    text = ''
      ${cfgLib.bashLib}

      LOCAL_PUB=${cfgLib.getKnown "paths.local-pub"}
      RECIPIENTS_DIR=${cfgLib.getKnown "secrets.recipients-dir"}

      usage() {
        echo "Usage: secrets:join [--group GROUP] [--name USERNAME]"
        echo ""
        echo "Add your local AGE public key to a recipient group."
        echo "This registers you to receive secrets after the next rekey."
        echo ""
        echo "Options:"
        echo "  --group   Recipient group (default: team)"
        echo "  --name    Your username (default: git config user.name or whoami)"
        exit 1
      }

      GROUP="team"
      USERNAME=""

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --group|-g)
            GROUP="$2"
            shift 2
            ;;
          --name|-n)
            USERNAME="$2"
            shift 2
            ;;
          -h|--help)
            usage
            ;;
          *)
            echo "Unknown option: $1" >&2
            usage
            ;;
        esac
      done

      # Determine username
      if [[ -z "$USERNAME" ]]; then
        USERNAME=$(git config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]') || true
        if [[ -z "$USERNAME" ]]; then
          USERNAME=$(whoami)
        fi
      fi

      # Check local key exists
      if [[ ! -f "$LOCAL_PUB" ]]; then
        echo "Error: No local key found at $LOCAL_PUB" >&2
        echo "Re-enter the devshell to auto-generate one." >&2
        exit 1
      fi

      PUB_KEY=$(cat "$LOCAL_PUB" | tr -d '[:space:]')
      if [[ -z "$PUB_KEY" ]]; then
        echo "Error: Local public key is empty" >&2
        exit 1
      fi

      # Create group directory
      GROUP_DIR="$RECIPIENTS_DIR/$GROUP"
      mkdir -p "$GROUP_DIR"

      # Write pub key
      OUTPUT_FILE="$GROUP_DIR/$USERNAME.age.pub"
      if [[ -f "$OUTPUT_FILE" ]]; then
        EXISTING=$(cat "$OUTPUT_FILE" | tr -d '[:space:]')
        if [[ "$EXISTING" == "$PUB_KEY" ]]; then
          echo "Your key is already registered in $GROUP/$USERNAME.age.pub"
          echo ""
          echo "If you're waiting for access, ask a teammate to rekey:"
          echo "  .stackpanel/secrets/bin/rekey.sh"
          exit 0
        fi
      fi

      echo "$PUB_KEY" > "$OUTPUT_FILE"
      echo "Added your key to $OUTPUT_FILE"
      echo ""
      echo "Public key: $PUB_KEY"
      echo ""

      # Offer to commit and push
      echo "Next steps:"
      echo "  1. git add $OUTPUT_FILE"
      echo "  2. git commit -m 'chore(secrets): add $USERNAME to $GROUP recipients'"
      echo "  3. git push (triggers rekey workflow)"
      echo ""
      echo "Or ask a teammate to run: .stackpanel/secrets/bin/rekey.sh"
    '';
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

  # ═══════════════════════════════════════════════════════════════════════════
  # Manifest: maps groups → keys, derived from stackpanel.variables
  # Generated as JSON at Nix eval time, written to state/ at shell entry.
  # ═══════════════════════════════════════════════════════════════════════════

  # Build manifest from variables config
  # Variables with keyGroup "computed" or "var" are excluded (not secrets).
  # Group each variable's varName by its keyGroup.
  secretVariables = lib.filterAttrs (
    _: v: v.keyGroup != "computed" && v.keyGroup != "var"
  ) config.stackpanel.variables;

  # Group variable names by keyGroup: { dev = ["DATABASE_URL" "API_KEY"]; prod = [...]; }
  keysByGroup = lib.foldlAttrs (
    acc: _: v:
    let
      group = v.keyGroup;
      name = v.varName;
      existing = acc.${group} or [ ];
    in
    acc // { ${group} = existing ++ [ name ]; }
  ) { } secretVariables;

  # Build the groups section of the manifest from Nix-known data
  # Note: recipient mapping comes from groups.json at runtime, not Nix eval time
  manifestGroups = lib.mapAttrs (
    groupName: _:
    let
      pub = orNull "" (cfg.groups.${groupName}.age-pub or null);
    in
    {
      initialized = pub != "";
    }
    // lib.optionalAttrs (groupName == "common") {
      keyedTo = "all-group-keys";
    }
  ) (keysByGroup // { common = [ ]; }); # ensure common is always present

  # The full manifest JSON
  manifestJson = builtins.toJSON {
    groups = manifestGroups;
    keysByGroup = keysByGroup;
  };

in
{
  imports = [
    ./options.nix
  ];

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
      pkgs.ssh-to-age
      sops-wrapped # wrapped sops that resolves keys from Nix config
      sops-age-keys
      secrets-init-group
      secrets-set
      secrets-get
      secrets-list
      secrets-rekey
      secrets-load
      secrets-join
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
        ${secretsLib.generateVarsSopsConfigScript { inherit groupsConfig; }}
        )
      ''
      # Generate v2 manifest.json in secrets state directory
      ''
        (
        SECRETS_STATE_DIR="${cfg.secrets-dir}/state"
        mkdir -p "$SECRETS_STATE_DIR"
        MANIFEST_FILE="$SECRETS_STATE_DIR/manifest.json"
        MANIFEST_CONTENT='${manifestJson}'
        # Only rewrite if content changed
        if [[ ! -f "$MANIFEST_FILE" ]] || [[ "$(cat "$MANIFEST_FILE" 2>/dev/null)" != "$MANIFEST_CONTENT" ]]; then
          echo "$MANIFEST_CONTENT" | ${pkgs.jq}/bin/jq '.' > "$MANIFEST_FILE"
        fi
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

      "secrets:load" = {
        exec = "${secrets-load}/bin/secrets-load \"$@\"";
        description = "Decrypt a SOPS vars file (dotenv, json, or yaml)";
        args = [
          {
            name = "group";
            description = "Group to decrypt (dev, prod, common, etc.)";
            required = true;
          }
          {
            name = "--format";
            description = "Output format: dotenv (default), json, yaml";
            default = "dotenv";
          }
        ];
      };

      "secrets:join" = {
        exec = "${secrets-join}/bin/secrets-join \"$@\"";
        description = "Add your local key to a recipient group";
        args = [
          {
            name = "--group";
            description = "Recipient group to join";
            default = "team";
          }
          {
            name = "--name";
            description = "Your username (default: git user.name or whoami)";
          }
        ];
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
      # Plaintext private keys (gitignored), but NOT .age.pub (public) or .enc.age (encrypted)
      ".stackpanel/secrets/recipients/*.age"
      "!.stackpanel/secrets/recipients/*.age.pub"
      "!.stackpanel/secrets/recipients/*.enc.age"
      # SSH ED25519 public keys in group dirs should be committed
      "!.stackpanel/secrets/recipients/**/*.ed25519.pub"
      # Archived rotated keys
      ".stackpanel/secrets/recipients/.archive/"
      # .vals files (contain refs to external stores, gitignored)
      ".stackpanel/secrets/recipients/*.vals"
      # Generated SOPS configs (regenerated on devshell entry)
      ".stackpanel/secrets/vars/.sops.yaml"
      ".stackpanel/secrets/recipients/.sops.yaml"
      # v2 state directory (generated artifacts)
      ".stackpanel/secrets/state/"
    ];

    # ═══════════════════════════════════════════════════════════════════════════
    # Generated README for secrets directory
    # ═══════════════════════════════════════════════════════════════════════════

    stackpanel.files.entries."${cfg.secrets-dir}/README.md" = {
      type = "text";
      description = "Generated secrets README";
      source = "secrets";
      text =
        let
          projectName = config.stackpanel.name;
          groupNames = lib.attrNames groupsConfig;
          groupList = lib.concatMapStringsSep "\n" (
            g:
            let
              pub = groupsConfig.${g}."age-pub" or "";
              status = if pub != "" then "initialized" else "not initialized";
            in
            "- **${g}** -- ${status}"
          ) groupNames;
          keysByGroupSection = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              group: keys: "- **${group}**: ${lib.concatStringsSep ", " (map (k: "`${k}`") keys)}"
            ) keysByGroup
          );
        in
        ''
          # Secrets

          Auto-generated secrets documentation for **${projectName}**.

          ## How It Works

          Secrets are stored in SOPS-encrypted YAML files, organized by **group** (e.g., `dev`, `prod`, `common`). Each group has its own AGE keypair for encryption/decryption. Variables reference their group via their ID prefix: a variable with ID `/dev/API_KEY` stores its encrypted value under the key `API_KEY` in `vars/dev.sops.yaml`.

          The `common` group is special -- it is encrypted to ALL group keys, so any group member can decrypt shared secrets.

          Variable values in `config.nix` are empty strings for secrets. The actual secret values live only in the SOPS files.

          ## Directory Structure

          ```
          ${cfg.secrets-dir}/
          ├── README.md               # This file (auto-generated)
          ├── vars/                    # SOPS-encrypted secret files
          │   ├── dev.sops.yaml        # Dev secrets
          │   ├── prod.sops.yaml       # Prod secrets
          │   ├── common.sops.yaml     # Shared secrets (encrypted to all groups)
          │   └── .sops.yaml           # Generated SOPS config (gitignored)
          ├── recipients/              # Recipient keys for team access
          │   ├── groups.json          # Group membership mapping
          │   ├── team/                # Default team recipient group
          │   │   └── <user>.age.pub   # Team member public keys
          │   └── admins/              # Admin recipient group
          │       └── <user>.age.pub   # Admin public keys
          ├── keys/                    # Local AGE keypair (gitignored)
          │   ├── local.age            # Private key
          │   └── local.age.pub        # Public key
          └── state/                   # Generated state (gitignored)
              └── manifest.json        # Current secrets manifest
          ```

          ## Quick Start

          ### 1. Join the team

          On first shell entry, a local AGE key is auto-generated. Register yourself as a recipient:

          ```bash
          secrets:join              # Join the default "team" group
          secrets:join --group admins  # Join the admins group
          ```

          After joining, commit your public key and push. A CI workflow will re-encrypt group keys for all recipients.

          ### 2. Set a secret

          ```bash
          secrets:set API_KEY --group dev --value 'sk_live_xxx'
          echo 'password123' | secrets:set DATABASE_URL --group prod
          ```

          ### 3. Read a secret

          ```bash
          secrets:get API_KEY                  # Reads from dev (default)
          secrets:get DATABASE_URL --group prod
          ```

          ### 4. List secrets

          ```bash
          secrets:list           # All groups
          secrets:list dev       # Only dev group
          ```

          ### 5. Load secrets into shell

          ```bash
          eval $(secrets:load dev)              # Export as env vars
          secrets:load dev --format json        # JSON output
          secrets:load common --format yaml     # YAML output
          ```

          ## Groups

          Groups control which AGE keypair encrypts a set of secrets.

          ### Configured Groups

          ${groupList}

          ### Initialize a new group

          ```bash
          secrets:init-group <name>              # Generate keypair, store in SSM
          secrets:init-group <name> --no-ssm     # Skip SSM storage
          secrets:init-group <name> --dry-run    # Preview only
          ```

          After initialization, add the group's public key to `config.nix` under `stackpanel.secrets.groups.<name>.age-pub`.

          ## Variable ID Convention

          Variable IDs encode their group: `/<group>/<key>`

          - `/dev/API_KEY` -- stored in `vars/dev.sops.yaml` under key `API_KEY`
          - `/prod/DATABASE_URL` -- stored in `vars/prod.sops.yaml` under key `DATABASE_URL`
          - `/common/SHARED_TOKEN` -- stored in `vars/common.sops.yaml`, encrypted to all groups

          Non-secret variables use `/var/<key>` (plaintext config) or `/computed/<key>` (derived values).

          ${lib.optionalString (keysByGroup != { }) ''
            ## Current Secrets by Group

            ${keysByGroupSection}
          ''}
          ## Other Commands

          | Command | Description |
          |---|---|
          | `secrets:show-keys` | Show all configured master keys and groups |
          | `secrets:rekey <id> --keys k1,k2` | Re-encrypt a secret to different keys |

          ## Standalone Scripts (`bin/`)

          The `bin/` directory contains portable shell scripts that work **without the Nix devshell**. They only need `sops`, `age`, and `jq` in PATH.

          | Script | Description |
          |---|---|
          | `bin/rekey.sh [group]` | Re-encrypt `.enc.age` files to all current recipients |
          | `bin/rotate.sh <group>` | Rotate a group's AGE keypair (archive old, generate new, re-encrypt) |
          | `bin/decrypt.sh <group>\|--all` | Decrypt `.enc.age` to plaintext `.age` for local use |
          | `bin/add-recipient.sh --key <key> --name <name> [--group <group>]` | Add a public key to a recipient group |
          | `bin/codegen.sh [--app <name>]` | Generate typed TypeScript env modules from secrets config |

          Use these in CI/CD pipelines or environments where Nix isn't available.

          ## How Encryption Works

          1. **SOPS** encrypts YAML files using AGE public keys from `config.nix`
          2. **Decryption** uses `SOPS_AGE_KEY_CMD` which lazily resolves keys from: local key, recipient `.age` files, `.enc.age` group keys, or per-group `key-cmd`
          3. **Recipients** get access when their public key is added and group keys are re-encrypted via CI
          4. **No vals references** -- secret values live directly in SOPS files, not as `ref+sops://` pointers
        '';
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
