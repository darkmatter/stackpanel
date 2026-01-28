# ==============================================================================
# lib.nix
#
# Master key-based secrets library.
#
# Provides functions for:
# - Resolving master key private keys (via vals or custom commands)
# - Auto-generating the local master key
# - Encrypting/decrypting secrets with master keys
#
# This replaces the previous user-based key system with a simpler model:
# - A few master keys encrypt all secrets
# - Each secret specifies which master keys can decrypt it
# - Keys are resolved at runtime via vals or custom commands
#
# All paths are resolved via cfg.nix with precedence:
#   1. Environment variable (runtime override)
#   2. CLI query (stackpanel config get)
#   3. Default (from knownPaths registry)
# ==============================================================================
{
  pkgs,
  lib,
  secretsDir ? ".stackpanel/secrets",
  ...
}:
let
  # Import cfg for consistent path resolution
  cfg = import ../lib/cfg.nix { inherit lib; };
in
rec {
  # ===========================================================================
  # Local Key Management
  # ===========================================================================

  # Script to auto-generate the local master key if it doesn't exist
  # This ensures secrets can always be created on first use
  autoGenerateLocalKeyScript = ''
    ${cfg.bashLib}

    STATE_DIR=${cfg.getKnown "paths.state"}
    KEYS_DIR=${cfg.getKnown "paths.keys"}
    LOCAL_KEY=${cfg.getKnown "paths.local-key"}
    LOCAL_PUB=${cfg.getKnown "paths.local-pub"}

    # Check if local key already exists
    if [[ -f "$LOCAL_KEY" ]]; then
      exit 0
    fi

    echo "🔐 Generating local master key..." >&2

    # Create keys directory with secure permissions
    mkdir -p "$KEYS_DIR"
    chmod 700 "$KEYS_DIR"

    # Generate new AGE key pair
    ${pkgs.age}/bin/age-keygen -o "$LOCAL_KEY" 2>/dev/null
    chmod 600 "$LOCAL_KEY"

    # Extract and save public key
    PUBLIC_KEY=$(${pkgs.age}/bin/age-keygen -y "$LOCAL_KEY")
    echo "$PUBLIC_KEY" > "$LOCAL_PUB"

    echo "✅ Local master key generated:" >&2
    echo "   Private: $LOCAL_KEY" >&2
    echo "   Public:  $PUBLIC_KEY" >&2
    echo "" >&2
    echo "💡 This key is local to your machine." >&2
    echo "   For team access, add shared master keys to stackpanel.secrets.master-keys" >&2
  '';

  # Get the local public key (reads from file if exists)
  getLocalPublicKeyScript = ''
    ${cfg.bashLib}

    LOCAL_PUB=${cfg.getKnown "paths.local-pub"}
    if [[ -f "$LOCAL_PUB" ]]; then
      cat "$LOCAL_PUB"
    else
      echo ""
    fi
  '';

  # ===========================================================================
  # Master Key Resolution
  # ===========================================================================

  # Resolve a master key's private key using vals or custom command
  # Takes the master key config and returns the private key
  resolveMasterKeyScript = ''
    resolve_master_key() {
      local KEY_NAME="$1"
      local REF="$2"
      local RESOLVE_CMD="$3"

      if [[ -n "$RESOLVE_CMD" ]]; then
        # Use custom resolve command
        eval "$RESOLVE_CMD"
      elif [[ "$REF" == ref+file://* ]]; then
        # File reference - read directly
        local FILE_PATH="''${REF#ref+file://}"
        if [[ -f "$FILE_PATH" ]]; then
          cat "$FILE_PATH"
        else
          echo "Error: Key file not found: $FILE_PATH" >&2
          return 1
        fi
      else
        # Use vals to resolve
        ${pkgs.vals}/bin/vals eval "$REF"
      fi
    }
  '';

  # Try to decrypt using any available master key
  # Tries each key in order until one succeeds
  tryDecryptScript = ''
    ${resolveMasterKeyScript}

    try_decrypt() {
      local AGE_FILE="$1"
      shift
      # Remaining args are: key_name ref resolve_cmd key_name ref resolve_cmd ...

      while [[ $# -ge 2 ]]; do
        local KEY_NAME="$1"
        local REF="$2"
        local RESOLVE_CMD="''${3:-}"
        shift 3 2>/dev/null || shift 2

        # Try to resolve this key
        local PRIVATE_KEY
        PRIVATE_KEY=$(resolve_master_key "$KEY_NAME" "$REF" "$RESOLVE_CMD" 2>/dev/null)

        if [[ -n "$PRIVATE_KEY" ]]; then
          # Try to decrypt with this key
          local DECRYPTED
          if DECRYPTED=$(echo "$PRIVATE_KEY" | ${pkgs.age}/bin/age -d -i - "$AGE_FILE" 2>/dev/null); then
            echo "$DECRYPTED"
            return 0
          fi
        fi
      done

      echo "Error: Could not decrypt $AGE_FILE with any available master key" >&2
      return 1
    }
  '';

  # ===========================================================================
  # Encryption
  # ===========================================================================

  # Encrypt a value to specified master keys
  # Usage: encrypt_to_master_keys "value" "output.age" "pub1" "pub2" ...
  encryptToMasterKeysScript = ''
    encrypt_to_master_keys() {
      local VALUE="$1"
      local OUTPUT="$2"
      shift 2

      # Build recipient args
      local RECIPIENTS=()
      for PUB in "$@"; do
        if [[ -n "$PUB" ]]; then
          RECIPIENTS+=("-r" "$PUB")
        fi
      done

      if [[ ''${#RECIPIENTS[@]} -eq 0 ]]; then
        echo "Error: No public keys provided for encryption" >&2
        return 1
      fi

      # Create parent directory if needed
      mkdir -p "$(dirname "$OUTPUT")"

      # Encrypt
      echo "$VALUE" | ${pkgs.age}/bin/age "''${RECIPIENTS[@]}" -o "$OUTPUT"
    }
  '';

  # ===========================================================================
  # Secret Management Scripts
  # ===========================================================================

  # Set a secret value (encrypt to specified master keys)
  setSecretScript = { masterKeysConfig }: ''
    set -e

    ${cfg.bashLib}
    ${encryptToMasterKeysScript}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    MASTER_KEYS_JSON='${builtins.toJSON masterKeysConfig}'

    usage() {
      echo "Usage: secrets:set <variable-id> [--keys key1,key2,...] [--value VALUE]"
      echo ""
      echo "Set a secret value, encrypting it to the specified master keys."
      echo ""
      echo "Options:"
      echo "  --keys    Comma-separated list of master key names (default: local)"
      echo "  --value   The secret value (if not provided, reads from stdin)"
      echo ""
      echo "Examples:"
      echo "  secrets:set /prod/api-key --keys prod --value 'sk_live_xxx'"
      echo "  echo 'password123' | secrets:set /dev/db-password --keys local,dev"
      exit 1
    }

    [[ $# -lt 1 ]] && usage

    VAR_ID="$1"
    shift

    KEYS="local"
    VALUE=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --keys)
          KEYS="$2"
          shift 2
          ;;
        --value)
          VALUE="$2"
          shift 2
          ;;
        *)
          echo "Unknown option: $1" >&2
          usage
          ;;
      esac
    done

    # Read from stdin if no value provided
    if [[ -z "$VALUE" ]]; then
      VALUE=$(cat)
    fi

    if [[ -z "$VALUE" ]]; then
      echo "Error: No value provided" >&2
      exit 1
    fi

    # Convert variable ID to filename
    FILENAME=$(echo "$VAR_ID" | sed 's|^/||' | tr '/' '-')
    OUTPUT_FILE="$SECRETS_DIR/$FILENAME.age"

    # Collect public keys for specified master keys
    PUBLIC_KEYS=()
    IFS=',' read -ra KEY_NAMES <<< "$KEYS"
    for KEY_NAME in "''${KEY_NAMES[@]}"; do
      PUB=$(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$KEY_NAME" '.[$name]["age-pub"] // empty')
      if [[ -n "$PUB" ]]; then
        PUBLIC_KEYS+=("$PUB")
        echo "   + $KEY_NAME ($PUB)"
      else
        echo "⚠️  Unknown master key: $KEY_NAME" >&2
      fi
    done

    if [[ ''${#PUBLIC_KEYS[@]} -eq 0 ]]; then
      echo "Error: No valid master keys found" >&2
      exit 1
    fi

    echo "🔒 Encrypting $VAR_ID to ''${#PUBLIC_KEYS[@]} master key(s)..."
    encrypt_to_master_keys "$VALUE" "$OUTPUT_FILE" "''${PUBLIC_KEYS[@]}"

    echo "✅ Secret saved: $OUTPUT_FILE"
  '';

  # Get a secret value (decrypt using available master keys)
  getSecretScript = { masterKeysConfig }: ''
    set -e

    ${cfg.bashLib}
    ${tryDecryptScript}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    MASTER_KEYS_JSON='${builtins.toJSON masterKeysConfig}'

    usage() {
      echo "Usage: secrets:get <variable-id>"
      echo ""
      echo "Get a decrypted secret value."
      exit 1
    }

    [[ $# -lt 1 ]] && usage

    VAR_ID="$1"

    # Convert variable ID to filename
    FILENAME=$(echo "$VAR_ID" | sed 's|^/||' | tr '/' '-')
    AGE_FILE="$SECRETS_DIR/$FILENAME.age"

    if [[ ! -f "$AGE_FILE" ]]; then
      echo "Error: Secret file not found: $AGE_FILE" >&2
      exit 1
    fi

    # Build args for try_decrypt: key_name ref resolve_cmd ...
    DECRYPT_ARGS=()
    for KEY_NAME in $(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
      REF=$(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r --arg k "$KEY_NAME" '.[$k].ref')
      RESOLVE_CMD=$(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r --arg k "$KEY_NAME" '.[$k]["resolve-cmd"] // ""')
      DECRYPT_ARGS+=("$KEY_NAME" "$REF" "$RESOLVE_CMD")
    done

    try_decrypt "$AGE_FILE" "''${DECRYPT_ARGS[@]}"
  '';

  # List all secrets
  listSecretsScript = ''
    ${cfg.bashLib}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}

    echo "Secrets in $SECRETS_DIR:"
    echo ""

    if [[ -d "$SECRETS_DIR" ]]; then
      shopt -s nullglob
      for f in "$SECRETS_DIR"/*.age; do
        [[ -f "$f" ]] || continue
        BASENAME=$(basename "$f" .age)
        # Convert filename back to variable ID format
        VAR_ID=$(echo "$BASENAME" | sed 's/-/\//g' | sed 's/^/\//')
        echo "  $VAR_ID"
      done
    else
      echo "  (no secrets directory)"
    fi
  '';

  # ===========================================================================
  # Group Key Management
  # ===========================================================================

  # Initialize a secrets group: generate AGE keypair and store private key in SSM.
  # Usage: secrets:init-group <group-name> [--ssm-path /custom/path] [--dry-run] [--yes]
  initGroupScript = { groupsConfig, chamberPrefix }: ''
    set -e

    ${cfg.bashLib}

    GROUPS_JSON='${builtins.toJSON groupsConfig}'

    usage() {
      echo "Usage: secrets:init-group <group-name> [--ssm-path PATH] [--dry-run] [--yes]"
      echo ""
      echo "Initialize a secrets group by generating an AGE keypair and storing"
      echo "the private key in AWS SSM Parameter Store."
      echo ""
      echo "Options:"
      echo "  --ssm-path  Override the SSM path (default: from group config)"
      echo "  --dry-run   Generate keypair and show what would happen, don't write to SSM"
      echo "  --yes       Skip confirmation prompt (for non-interactive use)"
      echo ""
      echo "Available groups:"
      echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]' | while read -r g; do
        SSM=$(echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq -r --arg g "$g" '.[$g]["ssm-path"] // "(default)"')
        echo "  $g  (ssm-path: $SSM)"
      done
      exit 1
    }

    [[ $# -lt 1 ]] && usage

    GROUP_NAME="$1"
    shift

    SSM_PATH_OVERRIDE=""
    DRY_RUN=false
    FORCE_YES=false
    JSON_OUTPUT=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --ssm-path)
          SSM_PATH_OVERRIDE="$2"
          shift 2
          ;;
        --dry-run)
          DRY_RUN=true
          shift
          ;;
        --yes|-y)
          FORCE_YES=true
          shift
          ;;
        --json)
          JSON_OUTPUT=true
          shift
          ;;
        *)
          echo "Unknown option: $1" >&2
          usage
          ;;
      esac
    done

    # Look up group config
    GROUP_EXISTS=$(echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq --arg g "$GROUP_NAME" 'has($g)')
    if [[ "$GROUP_EXISTS" != "true" ]]; then
      echo "Error: Unknown group '$GROUP_NAME'" >&2
      echo "" >&2
      echo "Available groups:" >&2
      echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]' | while read -r g; do
        echo "  $g" >&2
      done
      exit 1
    fi

    # Get SSM path
    if [[ -n "$SSM_PATH_OVERRIDE" ]]; then
      SSM_PATH="$SSM_PATH_OVERRIDE"
    else
      SSM_PATH=$(echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq -r --arg g "$GROUP_NAME" '.[$g]["ssm-path"]')
    fi

    # Check if group already has a public key configured
    EXISTING_PUB=$(echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq -r --arg g "$GROUP_NAME" '.[$g]["age-pub"] // ""')
    if [[ -n "$EXISTING_PUB" ]]; then
      echo "Warning: Group '$GROUP_NAME' already has a public key configured:" >&2
      echo "  $EXISTING_PUB" >&2
      echo "" >&2
      if [[ "$FORCE_YES" == "true" ]]; then
        echo "Overwriting (--yes specified)..." >&2
      else
        read -rp "Overwrite? This will generate a NEW keypair. [y/N] " CONFIRM
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
          echo "Aborted." >&2
          exit 0
        fi
      fi
    fi

    echo "Generating AGE keypair for group '$GROUP_NAME'..."

    # Generate keypair to a temp file
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    ${pkgs.age}/bin/age-keygen -o "$TMPDIR/key.txt" 2>/dev/null
    PRIVATE_KEY=$(cat "$TMPDIR/key.txt")
    PUBLIC_KEY=$(${pkgs.age}/bin/age-keygen -y "$TMPDIR/key.txt")

    # In JSON mode, all human-readable output goes to stderr
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      LOG() { echo "$@" >&2; }
    else
      LOG() { echo "$@"; }
    fi

    LOG ""
    LOG "Public key:  $PUBLIC_KEY"
    LOG "SSM path:    $SSM_PATH"
    LOG ""

    if [[ "$DRY_RUN" == "true" ]]; then
      if [[ "$JSON_OUTPUT" == "true" ]]; then
        ${pkgs.jq}/bin/jq -n \
          --arg group "$GROUP_NAME" \
          --arg publicKey "$PUBLIC_KEY" \
          --arg ssmPath "$SSM_PATH" \
          '{group: $group, publicKey: $publicKey, ssmPath: $ssmPath, dryRun: true}'
      else
        echo "[DRY RUN] Would store private key at SSM path: $SSM_PATH"
        echo ""
        echo "To complete setup, add to .stackpanel/config.nix:"
        echo ""
        echo "  stackpanel.secrets.groups.$GROUP_NAME.age-pub = \"$PUBLIC_KEY\";"
        echo ""
      fi
      exit 0
    fi

    # Store private key in SSM Parameter Store
    LOG "Storing private key in SSM Parameter Store..."

    # Use chamber if available and backend is chamber, otherwise use aws ssm directly
    CHAMBER_PREFIX="${chamberPrefix}"
    if command -v chamber &>/dev/null && [[ -n "$CHAMBER_PREFIX" ]]; then
      # Chamber stores under /{service}/keys/{group}
      # The SSM_PATH is already the full path, but chamber expects service + key format
      # We use aws ssm directly for precise path control
      ${pkgs.awscli2}/bin/aws ssm put-parameter \
        --name "$SSM_PATH" \
        --value "$PRIVATE_KEY" \
        --type SecureString \
        --overwrite \
        --description "AGE private key for stackpanel secrets group: $GROUP_NAME" \
        --tags "Key=Project,Value=${chamberPrefix}" "Key=ManagedBy,Value=stackpanel" \
        >&2 2>&1
    else
      ${pkgs.awscli2}/bin/aws ssm put-parameter \
        --name "$SSM_PATH" \
        --value "$PRIVATE_KEY" \
        --type SecureString \
        --overwrite \
        --description "AGE private key for stackpanel secrets group: $GROUP_NAME" \
        >&2 2>&1
    fi

    if [[ "$JSON_OUTPUT" == "true" ]]; then
      # Output clean JSON to stdout for machine consumption
      ${pkgs.jq}/bin/jq -n \
        --arg group "$GROUP_NAME" \
        --arg publicKey "$PUBLIC_KEY" \
        --arg ssmPath "$SSM_PATH" \
        '{group: $group, publicKey: $publicKey, ssmPath: $ssmPath, dryRun: false, success: true}'
    else
      echo ""
      echo "Done! Private key stored in SSM."
      echo ""
      echo "Next steps:"
      echo "  1. Add the public key to .stackpanel/config.nix (or data/secrets.nix):"
      echo ""
      echo "     stackpanel.secrets.groups.$GROUP_NAME.age-pub = \"$PUBLIC_KEY\";"
      echo ""
      echo "  2. Restart devshell to pick up the change"
      echo "  3. Secrets encrypted to this group will use the group's master key"
      echo ""
    fi
  '';

  # Re-encrypt a secret to different master keys
  rekeySecretScript = { masterKeysConfig }: ''
    set -e

    ${cfg.bashLib}
    ${tryDecryptScript}
    ${encryptToMasterKeysScript}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    MASTER_KEYS_JSON='${builtins.toJSON masterKeysConfig}'

    usage() {
      echo "Usage: secrets:rekey <variable-id> --keys key1,key2,..."
      echo ""
      echo "Re-encrypt a secret to different master keys."
      exit 1
    }

    [[ $# -lt 1 ]] && usage

    VAR_ID="$1"
    shift

    KEYS=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --keys)
          KEYS="$2"
          shift 2
          ;;
        *)
          echo "Unknown option: $1" >&2
          usage
          ;;
      esac
    done

    if [[ -z "$KEYS" ]]; then
      echo "Error: --keys is required" >&2
      usage
    fi

    # Convert variable ID to filename
    FILENAME=$(echo "$VAR_ID" | sed 's|^/||' | tr '/' '-')
    AGE_FILE="$SECRETS_DIR/$FILENAME.age"

    if [[ ! -f "$AGE_FILE" ]]; then
      echo "Error: Secret file not found: $AGE_FILE" >&2
      exit 1
    fi

    echo "🔄 Re-keying $VAR_ID..."

    # First, decrypt the current value
    DECRYPT_ARGS=()
    for KEY_NAME in $(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
      REF=$(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r --arg k "$KEY_NAME" '.[$k].ref')
      RESOLVE_CMD=$(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r --arg k "$KEY_NAME" '.[$k]["resolve-cmd"] // ""')
      DECRYPT_ARGS+=("$KEY_NAME" "$REF" "$RESOLVE_CMD")
    done

    VALUE=$(try_decrypt "$AGE_FILE" "''${DECRYPT_ARGS[@]}")

    # Collect new public keys
    PUBLIC_KEYS=()
    IFS=',' read -ra KEY_NAMES <<< "$KEYS"
    for KEY_NAME in "''${KEY_NAMES[@]}"; do
      PUB=$(echo "$MASTER_KEYS_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$KEY_NAME" '.[$name]["age-pub"] // empty')
      if [[ -n "$PUB" ]]; then
        PUBLIC_KEYS+=("$PUB")
        echo "   + $KEY_NAME"
      else
        echo "⚠️  Unknown master key: $KEY_NAME" >&2
      fi
    done

    # Re-encrypt with new keys
    encrypt_to_master_keys "$VALUE" "$AGE_FILE" "''${PUBLIC_KEYS[@]}"

    echo "✅ Secret re-keyed: $AGE_FILE"
  '';
}
