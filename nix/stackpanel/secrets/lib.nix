# ==============================================================================
# lib.nix
#
# Secrets helper library.
#
# Provides functions for:
# - Auto-generating the local AGE identity used by SOPS
# - Wrapping SOPS with the current local key command
# - Legacy master-key helpers that are still used by older code paths
#
# Directory structure:
#   .stack/secrets/
#   ├── apps.json               # per-app codegen metadata
#   ├── .sops.yaml              # generated SOPS creation rules
#   ├── vars/
#   │   └── <group>.sops.yaml   # mixed encrypted + plaintext values
#   #
#   # Standalone scripts live in secrets/bin/:
#   #   secrets/bin/rekey.sh        # re-encrypt vars/*.sops.yaml to current recipients
#   #   secrets/bin/codegen.sh      # run codegen standalone
#   #
#   # All paths are resolved via cfg.nix with precedence:
#   #   1. Environment variable (runtime override)
#   #   2. CLI query (stackpanel config get)
#   #   3. Default (from knownPaths registry)
# ==============================================================================
{
  pkgs,
  lib,
  secretsDir ? ".stack/secrets",
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

  # Script to auto-generate the local AGE key if it doesn't exist.
  autoGenerateLocalKeyScript = ''
    # syntax: bash
        ${cfg.bashLib}

        STATE_DIR=${cfg.getKnown "paths.state"}
        KEYS_DIR=${cfg.getKnown "paths.keys"}
        LOCAL_KEY=${cfg.getKnown "paths.local-key"}
        LOCAL_PUB=${cfg.getKnown "paths.local-pub"}

        if [[ ! -f "$LOCAL_KEY" ]]; then
          echo "Generating local AGE key..." >&2

          mkdir -p "$KEYS_DIR"
          chmod 700 "$KEYS_DIR"

          ${pkgs.age}/bin/age-keygen -o "$LOCAL_KEY" 2>/dev/null
          chmod 600 "$LOCAL_KEY"

          PUBLIC_KEY=$(${pkgs.age}/bin/age-keygen -y "$LOCAL_KEY")
          echo "$PUBLIC_KEY" > "$LOCAL_PUB"

          echo "" >&2
          echo "Local AGE key generated:" >&2
          echo "   Private: $LOCAL_KEY" >&2
          echo "   Public:  $PUBLIC_KEY" >&2
        fi
  '';

  # Wrapped SOPS that exports SOPS_AGE_KEY_CMD so the generated .sops.yaml can be
  # used directly for both encryption and decryption.
  sopsWrappedScript =
    {
      sopsAgeKeysPath,
      sopsKeyservices ? [ ],
      ...
    }:
    ''
      ${cfg.bashLib}

      export SOPS_AGE_KEY_CMD="${sopsAgeKeysPath}"
      ${lib.optionalString (
        sopsKeyservices != [ ]
      ) ''export SOPS_KEYSERVICE="${lib.concatStringsSep "," sopsKeyservices}"''}
      SECRETS_DIR=${cfg.getKnown "secrets.secrets-dir"}
      PROJECT_ROOT=${cfg.getKnown "paths.root"}
      SOPS_CONFIG_PATH="$PROJECT_ROOT/.sops.yaml"

      resolve_target_path() {
        local candidate="$1"

        [[ -z "$candidate" ]] && return 1

        if [[ "$candidate" == /* ]]; then
          printf '%s\n' "$candidate"
          return 0
        fi

        if [[ "$candidate" == ./* ]]; then
          local trimmed_candidate
          trimmed_candidate="''${candidate#./}"
          printf '%s\n' "$PWD/$trimmed_candidate"
          return 0
        fi

        if [[ -n "$PROJECT_ROOT" ]]; then
          printf '%s\n' "$PROJECT_ROOT/$candidate"
          return 0
        fi

        printf '%s\n' "$PWD/$candidate"
      }

      EXTRA_ARGS=()
      for arg in "$@"; do
        case "$arg" in
          -*)
            continue
            ;;
        esac

        resolved="$(resolve_target_path "$arg" 2>/dev/null || true)"
        case "$resolved" in
          "$PROJECT_ROOT/.stack/secrets"/*|"$PROJECT_ROOT/.stack/secrets"/*|"$SECRETS_DIR"/*)
            if [[ -f "$SOPS_CONFIG_PATH" ]]; then
              EXTRA_ARGS+=(--config "$SOPS_CONFIG_PATH")
            fi
            break
            ;;
        esac
      done

      exec ${pkgs.sops}/bin/sops "''${EXTRA_ARGS[@]}" "$@"
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

  # Set a secret value in a SOPS-encrypted group YAML file
  #
  # Usage (all positional, all optional — prompts for anything missing):
  #   secrets:set                        # prompts for group, key, value
  #   secrets:set dev                    # prompts for key, value
  #   secrets:set dev api-key            # prompts for value
  #   secrets:set dev api-key 'sk_xxx'   # no prompts
  setSecretScript = ''
    set -e

    ${cfg.bashLib}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    VARS_DIR="$SECRETS_DIR/vars"

    # ── helpers ────────────────────────────────────────────────────────────────

    list_groups() {
      shopt -s nullglob
      local files=("$VARS_DIR"/*.sops.yaml)
      local names=()
      for f in "''${files[@]}"; do
        names+=("$(basename "$f" .sops.yaml)")
      done
      printf '%s\n' "''${names[@]}"
    }

    pick_group() {
      local groups
      groups=$(list_groups)
      if [[ -z "$groups" ]]; then
        echo "No group files found in $VARS_DIR" >&2
        echo "dev"
        return
      fi
      printf '%s\n' "$groups" | gum choose --header "Select a group:"
    }

    validate_key() {
      local key="$1"
      if [[ ! "$key" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        echo "Invalid key: '$key'" >&2
        echo "Keys must be lowercase alphanumeric + hyphens, starting with a letter or number." >&2
        return 1
      fi
    }

    # ── parse positional args ──────────────────────────────────────────────────

    GROUP="''${1:-}"
    KEY="''${2:-}"
    VALUE="''${3:-}"

    # ── interactive prompts for anything missing ───────────────────────────────

    if [[ -z "$GROUP" ]]; then
      GROUP=$(pick_group)
    fi

    if [[ -z "$KEY" ]]; then
      KEY=$(gum input --prompt "Key: " --placeholder "e.g. api-key")
    fi

    validate_key "$KEY"

    if [[ -z "$VALUE" ]]; then
      # Use gum write for multi-line support; ctrl+d to confirm
      VALUE=$(gum input --prompt "Value: " --placeholder "(leave empty to read from stdin)" --password)
      if [[ -z "$VALUE" ]]; then
        VALUE=$(cat)
      fi
    fi

    if [[ -z "$VALUE" ]]; then
      echo "Error: No value provided" >&2
      exit 1
    fi

    # ── write ─────────────────────────────────────────────────────────────────

    GROUP_FILE="$VARS_DIR/$GROUP.sops.yaml"

    if [[ ! -f "$GROUP_FILE" ]]; then
      echo "Creating new group file: $GROUP_FILE"
      mkdir -p "$VARS_DIR"
      echo "_init: true" > "$GROUP_FILE"
      sops --encrypt --in-place "$GROUP_FILE"
    fi

    echo "Setting $KEY in $GROUP..."
    sops set "$GROUP_FILE" "[\"$KEY\"]" "\"$VALUE\""

    # Remove the _init placeholder if present
    HAS_INIT=$(sops decrypt "$GROUP_FILE" 2>/dev/null | ${pkgs.yq-go}/bin/yq 'has("_init")' 2>/dev/null) || true
    if [[ "$HAS_INIT" == "true" ]]; then
      sops decrypt "$GROUP_FILE" | ${pkgs.yq-go}/bin/yq 'del(._init)' > "$GROUP_FILE.tmp"
      mv "$GROUP_FILE.tmp" "$GROUP_FILE"
      sops --encrypt --in-place "$GROUP_FILE"
    fi

    echo "Saved: $KEY → $GROUP_FILE"
  '';

  # Get a secret value from a SOPS-encrypted group YAML file
  #
  # Usage (all positional, all optional — prompts for anything missing):
  #   secrets:get                  # prompts for group, then key
  #   secrets:get dev              # prompts for key
  #   secrets:get dev api-key      # no prompts
  getSecretScript = ''
    set -e

    ${cfg.bashLib}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    VARS_DIR="$SECRETS_DIR/vars"

    # ── helpers ────────────────────────────────────────────────────────────────

    list_groups() {
      shopt -s nullglob
      local files=("$VARS_DIR"/*.sops.yaml)
      local names=()
      for f in "''${files[@]}"; do
        names+=("$(basename "$f" .sops.yaml)")
      done
      printf '%s\n' "''${names[@]}"
    }

    pick_group() {
      local groups
      groups=$(list_groups)
      if [[ -z "$groups" ]]; then
        echo "No group files found in $VARS_DIR" >&2
        exit 1
      fi
      printf '%s\n' "$groups" | gum choose --header "Select a group:"
    }

    pick_key() {
      local group_file="$1"
      local keys
      keys=$(${pkgs.sops}/bin/sops decrypt "$group_file" 2>/dev/null \
        | ${pkgs.yq-go}/bin/yq 'keys | .[] | select(. != "_init")' 2>/dev/null) || {
        echo "Could not list keys (decryption failed?)" >&2
        exit 1
      }
      if [[ -z "$keys" ]]; then
        echo "No keys found in $group_file" >&2
        exit 1
      fi
      printf '%s\n' "$keys" | gum choose --header "Select a key:"
    }

    # ── parse positional args ──────────────────────────────────────────────────

    GROUP="''${1:-}"
    KEY="''${2:-}"

    # ── interactive prompts for anything missing ───────────────────────────────

    if [[ -z "$GROUP" ]]; then
      GROUP=$(pick_group)
    fi

    GROUP_FILE="$VARS_DIR/$GROUP.sops.yaml"

    if [[ ! -f "$GROUP_FILE" ]]; then
      echo "Error: Group file not found: $GROUP_FILE" >&2
      echo "Available groups:" >&2
      list_groups | while IFS= read -r g; do echo "  $g" >&2; done
      exit 1
    fi

    if [[ -z "$KEY" ]]; then
      KEY=$(pick_key "$GROUP_FILE")
    fi

    # ── fetch ─────────────────────────────────────────────────────────────────

    RESULT=$(${pkgs.sops}/bin/sops decrypt --extract "[\"$KEY\"]" "$GROUP_FILE" 2>/dev/null) || {
      echo "Error: key '$KEY' not found in group '$GROUP', or decryption failed." >&2
      echo "Available keys:" >&2
      ${pkgs.sops}/bin/sops decrypt "$GROUP_FILE" 2>/dev/null \
        | ${pkgs.yq-go}/bin/yq 'keys | .[] | select(. != "_init")' 2>/dev/null \
        | while IFS= read -r k; do echo "  $k" >&2; done \
        || echo "  (could not list keys)" >&2
      exit 1
    }

    echo "$RESULT"
  '';

  # List all secrets across SOPS-encrypted group YAML files
  # Usage: secrets:list [GROUP]
  listSecretsScript = ''
    set -e

    ${cfg.bashLib}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    VARS_DIR="$SECRETS_DIR/vars"

    GROUP_FILTER="''${1:-}"

    if [[ ! -d "$VARS_DIR" ]]; then
      echo "No vars directory found at $VARS_DIR"
      exit 0
    fi

    shopt -s nullglob
    GROUP_FILES=("$VARS_DIR"/*.sops.yaml)

    if [[ ''${#GROUP_FILES[@]} -eq 0 ]]; then
      echo "No group files found in $VARS_DIR"
      exit 0
    fi

    for GROUP_FILE in "''${GROUP_FILES[@]}"; do
      [[ -f "$GROUP_FILE" ]] || continue
      GROUP_NAME=$(basename "$GROUP_FILE" .sops.yaml)

      # If a filter is provided, skip non-matching groups
      if [[ -n "$GROUP_FILTER" && "$GROUP_NAME" != "$GROUP_FILTER" ]]; then
        continue
      fi

      echo "$GROUP_NAME:"

      # Decrypt and list keys
      KEYS=$(${pkgs.sops}/bin/sops decrypt "$GROUP_FILE" 2>/dev/null | ${pkgs.yq-go}/bin/yq 'keys | .[] | select(. != "_init")' 2>/dev/null) || {
        echo "  (could not decrypt - missing key?)"
        echo ""
        continue
      }

      if [[ -z "$KEYS" ]]; then
        echo "  (empty)"
      else
        while IFS= read -r line; do echo "  $line"; done <<< "$KEYS"
      fi
      echo ""
    done
  '';

  # ===========================================================================
  # Per-variable Secret Rekeying
  # ===========================================================================

  # Re-encrypt a secret to different master keys
  rekeySecretScript =
    { masterKeysConfig }:
    ''
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

      echo "Re-keying $VAR_ID..."

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
          echo "Warning: Unknown master key: $KEY_NAME" >&2
        fi
      done

      # Re-encrypt with new keys
      encrypt_to_master_keys "$VALUE" "$AGE_FILE" "''${PUBLIC_KEYS[@]}"

      echo "Secret re-keyed: $AGE_FILE"
    '';
}
