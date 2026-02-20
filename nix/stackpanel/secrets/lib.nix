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

  # GitHub Actions workflow template for secrets re-keying.
  # Kept as a separate file to avoid Nix string interpolation escaping issues
  # with ${...} syntax used by bash and GitHub Actions expressions.
  rekeyWorkflowTemplate = ./secrets-rekey-workflow.yml.tpl;
in
rec {
  # ===========================================================================
  # Local Key Management
  # ===========================================================================

  # Script to auto-generate the local master key if it doesn't exist,
  # register the local public key in the recipients directory (for team access),
  # and ensure keys/.sops.yaml exists with ALL recipients for SOPS encryption
  # of .enc.age files.
  autoGenerateLocalKeyScript = ''
        ${cfg.bashLib}

        STATE_DIR=${cfg.getKnown "paths.state"}
        KEYS_DIR=${cfg.getKnown "paths.keys"}
        LOCAL_KEY=${cfg.getKnown "paths.local-key"}
        LOCAL_PUB=${cfg.getKnown "paths.local-pub"}
        SECRETS_KEYS_DIR=${cfg.getKnown "secrets.keys-dir"}
        RECIPIENTS_DIR=${cfg.getKnown "secrets.recipients-dir"}

        KEY_GENERATED=false

        # Generate local key if it doesn't exist
        if [[ ! -f "$LOCAL_KEY" ]]; then
          echo "Generating local master key..." >&2

          # Create keys directory with secure permissions
          mkdir -p "$KEYS_DIR"
          chmod 700 "$KEYS_DIR"

          # Generate new AGE key pair
          ${pkgs.age}/bin/age-keygen -o "$LOCAL_KEY" 2>/dev/null
          chmod 600 "$LOCAL_KEY"

          # Extract and save public key
          PUBLIC_KEY=$(${pkgs.age}/bin/age-keygen -y "$LOCAL_KEY")
          echo "$PUBLIC_KEY" > "$LOCAL_PUB"

          echo "Local master key generated:" >&2
          echo "   Private: $LOCAL_KEY" >&2
          echo "   Public:  $PUBLIC_KEY" >&2

          KEY_GENERATED=true
        fi

    # Register local public key in the recipients directory.
    # This directory is committed to git so team members can be added
    # by simply pushing their .pub file.
    mkdir -p "$RECIPIENTS_DIR"
    if [[ -f "$LOCAL_PUB" ]]; then
      LOCAL_PUB_KEY=$(cat "$LOCAL_PUB")
      # Use git username, system username, or key fingerprint as filename
      RECIPIENT_NAME=""
      if command -v git &>/dev/null; then
        RECIPIENT_NAME=$(git config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
      fi
      if [[ -z "$RECIPIENT_NAME" ]]; then
        RECIPIENT_NAME=$(whoami 2>/dev/null || echo "local")
      fi

      RECIPIENT_FILE="$RECIPIENTS_DIR/$RECIPIENT_NAME.pub"
      if [[ ! -f "$RECIPIENT_FILE" ]] || [[ "$(cat "$RECIPIENT_FILE")" != "$LOCAL_PUB_KEY" ]]; then
        echo "$LOCAL_PUB_KEY" > "$RECIPIENT_FILE"
        if [[ "$KEY_GENERATED" == "true" ]]; then
          echo "" >&2
          echo "Registered as recipient: $RECIPIENT_NAME" >&2
          echo "   Commit and push $RECIPIENT_FILE to get team access." >&2
        fi
      fi
    fi

    # Ensure keys/.sops.yaml exists and includes ALL recipients from the
    # recipients directory. This allows any team member whose .pub is committed
    # to decrypt .enc.age files (group private keys).
    KEYS_SOPS_YAML="$SECRETS_KEYS_DIR/.sops.yaml"

    # Collect all recipient public keys
    ALL_PUBS=""
    if [[ -d "$RECIPIENTS_DIR" ]]; then
      for pub_file in "$RECIPIENTS_DIR"/*.pub; do
        [[ -f "$pub_file" ]] || continue
        PUB_KEY=$(cat "$pub_file" | tr -d '[:space:]')
        if [[ -n "$PUB_KEY" ]]; then
          ALL_PUBS="$ALL_PUBS $PUB_KEY"
        fi
      done
    fi
    # Trim leading space
    ALL_PUBS=$(echo "$ALL_PUBS" | sed 's/^ //')

    # Check if regeneration is needed
    NEEDS_REGEN=false
    if [[ ! -f "$KEYS_SOPS_YAML" ]]; then
      NEEDS_REGEN=true
    elif grep -q "age: \[\]" "$KEYS_SOPS_YAML" 2>/dev/null; then
      NEEDS_REGEN=true
    else
      # Check if current .sops.yaml matches the recipients we expect.
      # Extract existing age keys from .sops.yaml and compare with ALL_PUBS.
      EXISTING_PUBS=$(grep -oE 'age1[a-z0-9]+' "$KEYS_SOPS_YAML" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')
      EXPECTED_PUBS=$(echo "$ALL_PUBS" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
      if [[ "$EXISTING_PUBS" != "$EXPECTED_PUBS" ]]; then
        NEEDS_REGEN=true
      fi
    fi

    if [[ "$NEEDS_REGEN" == "true" && -n "$ALL_PUBS" ]]; then
      # Build the age recipients YAML list
      AGE_LINES=""
      for PUB_KEY in $ALL_PUBS; do
        AGE_LINES="$AGE_LINES
              - $PUB_KEY"
      done

          cat > "$KEYS_SOPS_YAML" << SOPSEOF
    # SOPS configuration for group encryption keys
    #
    # Auto-generated by stackpanel from .stackpanel/secrets/keys/recipients/*.pub
    # DO NOT EDIT - changes will be overwritten. To add recipients, add .pub files
    # to the recipients directory and re-enter the devshell.

    creation_rules:
      - path_regex: \.enc\.age$
        key_groups:
          - age:$AGE_LINES
    SOPSEOF
          echo "Generated $KEYS_SOPS_YAML with $(echo "$ALL_PUBS" | wc -w | tr -d ' ') recipient(s)" >&2
        fi
  '';

  # Generate groups/.sops.yaml from Nix config (single source of truth).
  # This ensures the SOPS config always matches what's defined in config.nix,
  # eliminating key drift between .sops.yaml files and the Nix config.
  # Takes: { groupsConfig } where groupsConfig is the attrset of
  #   group-name -> { age-pub } from config.nix
  generateGroupsSopsConfigScript =
    { groupsConfig }:
    let
      # Build JSON of group name -> age-pub for use in bash
      groupPubKeys = lib.filterAttrs (_: v: v.age-pub != null && v.age-pub != "") groupsConfig;
      groupsJson = builtins.toJSON (lib.mapAttrs (_: v: v.age-pub) groupPubKeys);
    in
    ''
          ${cfg.bashLib}

          GROUPS_DIR=${cfg.getKnown "secrets.groups-dir"}
          GROUPS_JSON='${groupsJson}'

          mkdir -p "$GROUPS_DIR"

          # Build .sops.yaml from the Nix-defined group public keys.
          # Each group YAML file is encrypted to that group's AGE key.
          SOPS_YAML="$GROUPS_DIR/.sops.yaml"

          # Build expected content
          EXPECTED="# Auto-generated from config.nix — DO NOT EDIT.
      # Group public keys are defined in stackpanel.secrets.groups.<name>.age-pub.
      # To change a group key, update config.nix and re-enter the devshell.
      creation_rules:"

          # Add a creation rule per group
          for GROUP_NAME in $(echo "$GROUPS_JSON" | jq -r 'keys[]' | sort); do
            AGE_PUB=$(echo "$GROUPS_JSON" | jq -r --arg g "$GROUP_NAME" '.[$g]')
            EXPECTED="''${EXPECTED}
        - path_regex: ^''${GROUP_NAME}\\.yaml$
          key_groups:
            - age:
                - ''${AGE_PUB}"
          done

          # Only rewrite if content changed
          if [[ -f "$SOPS_YAML" ]]; then
            CURRENT=$(cat "$SOPS_YAML")
          else
            CURRENT=""
          fi

           if [[ "$EXPECTED" != "$CURRENT" ]]; then
            echo "$EXPECTED" > "$SOPS_YAML"
            echo "Generated $SOPS_YAML from config.nix group keys" >&2
          fi
    '';

  # Wrapped SOPS that resolves AGE recipients from Nix config.
  # Instead of relying on .sops.yaml creation_rules for recipient routing,
  # this wrapper inspects the file path, maps group-name -> age-pub from
  # the Nix-embedded JSON, and passes --age <pubkey> to real sops.
  # This makes Nix config the authoritative source for encryption keys.
  # Takes: { groupsConfig, sopsAgeKeysPath } where:
  #   - groupsConfig is the group-name -> { age-pub } attrset
  #   - sopsAgeKeysPath is the path to the sops-age-keys script (for SOPS_AGE_KEY_CMD)
  sopsWrappedScript =
    { groupsConfig, sopsAgeKeysPath }:
    let
      groupPubKeys = lib.filterAttrs (_: v: v.age-pub != null && v.age-pub != "") groupsConfig;
      groupsJson = builtins.toJSON (lib.mapAttrs (_: v: v.age-pub) groupPubKeys);
    in
    ''
      GROUPS_JSON='${groupsJson}'

      # Export SOPS_AGE_KEY_CMD so sops can decrypt (private keys)
      export SOPS_AGE_KEY_CMD="${sopsAgeKeysPath}"

      # Detect the group from the file path and inject --age <pubkey>
      # Scans all positional args for a file matching groups/<name>.yaml
      EXTRA_ARGS=()
      for arg in "$@"; do
        if [[ "$arg" =~ groups/([^/]+)\.yaml$ ]]; then
          GROUP_NAME="''${BASH_REMATCH[1]}"
          PUB_KEY=$(echo "$GROUPS_JSON" | jq -r --arg g "$GROUP_NAME" '.[$g] // empty')
          if [[ -n "$PUB_KEY" ]]; then
            EXTRA_ARGS+=(--age "$PUB_KEY")
          fi
          break
        fi
      done

      exec ${pkgs.sops}/bin/sops "''${EXTRA_ARGS[@]}" "$@"
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

  # Set a secret value in a SOPS-encrypted group YAML file
  # Usage: secrets:set <KEY> [--group GROUP] [--value VALUE]
  setSecretScript = ''
    set -e

    ${cfg.bashLib}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    GROUPS_DIR="$SECRETS_DIR/groups"

    usage() {
      echo "Usage: secrets:set <KEY> [--group GROUP] [--value VALUE]"
      echo ""
      echo "Set a secret value in a SOPS-encrypted group file."
      echo ""
      echo "Options:"
      echo "  --group   Target group (default: dev)"
      echo "  --value   The secret value (if not provided, reads from stdin)"
      echo ""
      echo "Examples:"
      echo "  secrets:set API_KEY --group dev --value 'sk_live_xxx'"
      echo "  echo 'password123' | secrets:set DATABASE_URL --group prod"
      exit 1
    }

    [[ $# -lt 1 ]] && usage

    KEY="$1"
    shift

    # Validate key: lowercase alphanumeric + hyphens only (chamber naming rules)
    if [[ ! "$KEY" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      LOG "ERROR" "Invalid key name: $KEY"
      LOG "ERROR" "Keys must contain only lowercase letters, numbers, and hyphens"
      LOG "ERROR" "Keys must start with a letter or number (not a hyphen)"
      exit 1
    fi

    GROUP="dev"
    VALUE=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --group|-g)
          GROUP="$2"
          shift 2
          ;;
        --value|-v)
          VALUE="$2"
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

    # Read from stdin if no value provided
    if [[ -z "$VALUE" ]]; then
      VALUE=$(cat)
    fi

    if [[ -z "$VALUE" ]]; then
      echo "Error: No value provided" >&2
      exit 1
    fi

    GROUP_FILE="$GROUPS_DIR/$GROUP.yaml"

    if [[ ! -f "$GROUP_FILE" ]]; then
      echo "Creating new group file: $GROUP_FILE"
      mkdir -p "$GROUPS_DIR"
      # Create an initial YAML with just a placeholder, then encrypt it
      echo "_init: true" > "$GROUP_FILE"
      sops --encrypt --in-place "$GROUP_FILE"
      # Remove the placeholder
    fi

    echo "Setting $KEY in $GROUP group..."
    sops set "$GROUP_FILE" "[\"$KEY\"]" "\"$VALUE\""

    # Remove the _init placeholder if it exists
    HAS_INIT=$(sops decrypt "$GROUP_FILE" 2>/dev/null | ${pkgs.yq-go}/bin/yq 'has("_init")' 2>/dev/null) || true
    if [[ "$HAS_INIT" == "true" ]]; then
      sops decrypt "$GROUP_FILE" | ${pkgs.yq-go}/bin/yq 'del(._init)' > "$GROUP_FILE.tmp"
      mv "$GROUP_FILE.tmp" "$GROUP_FILE"
      sops --encrypt --in-place "$GROUP_FILE"
    fi

    echo "Secret saved: $KEY in $GROUP_FILE"
  '';

  # Get a secret value from a SOPS-encrypted group YAML file
  # Usage: secrets:get <KEY> [--group GROUP]
  getSecretScript = ''
    set -e

    ${cfg.bashLib}

    SECRETS_DIR=${cfg.getWithDefault "secrets.secrets-dir" secretsDir}
    GROUPS_DIR="$SECRETS_DIR/groups"

    usage() {
      echo "Usage: secrets:get <KEY> [--group GROUP]"
      echo ""
      echo "Get a decrypted secret value from a SOPS group file."
      echo ""
      echo "Options:"
      echo "  --group   Source group (default: dev)"
      echo ""
      echo "Examples:"
      echo "  secrets:get API_KEY"
      echo "  secrets:get DATABASE_URL --group prod"
      exit 1
    }

    [[ $# -lt 1 ]] && usage

    KEY="$1"
    shift

    # Validate key: lowercase alphanumeric + hyphens only (chamber naming rules)
    if [[ ! "$KEY" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      LOG "ERROR" "Invalid key name: $KEY"
      LOG "ERROR" "Keys must contain only lowercase letters, numbers, and hyphens"
      exit 1
    fi

    GROUP="dev"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --group|-g)
          GROUP="$2"
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

    GROUP_FILE="$GROUPS_DIR/$GROUP.yaml"

    if [[ ! -f "$GROUP_FILE" ]]; then
      echo "Error: Group file not found: $GROUP_FILE" >&2
      echo "Available groups:"
      for f in "$GROUPS_DIR"/*.yaml; do
        [[ -f "$f" ]] && echo "  $(basename "$f" .yaml)"
      done
      exit 1
    fi

    # Extract the specific key value
    RESULT=$(${pkgs.sops}/bin/sops decrypt --extract "[\"$KEY\"]" "$GROUP_FILE" 2>/dev/null) || {
      echo "Error: Key '$KEY' not found in $GROUP group, or decryption failed." >&2
      echo "Available keys in $GROUP:"
      ${pkgs.sops}/bin/sops decrypt "$GROUP_FILE" 2>/dev/null | ${pkgs.yq-go}/bin/yq 'keys | .[]' 2>/dev/null | while IFS= read -r line; do echo "  $line"; done || echo "  (could not list keys)"
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
    GROUPS_DIR="$SECRETS_DIR/groups"

    GROUP_FILTER="''${1:-}"

    if [[ ! -d "$GROUPS_DIR" ]]; then
      echo "No groups directory found at $GROUPS_DIR"
      exit 0
    fi

    shopt -s nullglob
    GROUP_FILES=("$GROUPS_DIR"/*.yaml)

    if [[ ''${#GROUP_FILES[@]} -eq 0 ]]; then
      echo "No group files found in $GROUPS_DIR"
      exit 0
    fi

    for GROUP_FILE in "''${GROUP_FILES[@]}"; do
      [[ -f "$GROUP_FILE" ]] || continue
      GROUP_NAME=$(basename "$GROUP_FILE" .yaml)

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
  # Group Key Management
  # ===========================================================================

  # Initialize a secrets group: generate AGE keypair, encrypt private key with SOPS,
  # and optionally store in SSM.
  # Usage: secrets:init-group <group-name> [--ssm-path /custom/path] [--dry-run] [--yes] [--no-ssm]
  initGroupScript =
    { groupsConfig, chamberPrefix }:
    ''
                  set -e

                  ${cfg.bashLib}

                  GROUPS_JSON='${builtins.toJSON groupsConfig}'

                  usage() {
                    echo "Usage: secrets:init-group <group-name> [OPTIONS]"
                    echo ""
                    echo "Initialize a secrets group by generating an AGE keypair."
                    echo "The private key is encrypted with SOPS and stored as a .enc.age file."
                    echo "Optionally, it can also be stored in AWS SSM Parameter Store."
                    echo ""
                    echo "Options:"
                    echo "  --ssm-path  Override the SSM path (default: from group config)"
                    echo "  --no-ssm    Skip SSM storage (local .enc.age only)"
                    echo "  --no-gh     Skip GitHub Actions integration entirely"
                    echo "  --force-gh  Overwrite existing GitHub secret (default: skip if exists)"
                    echo "  --dry-run   Generate keypair and show what would happen, don't write"
                    echo "  --yes       Skip confirmation prompt (for non-interactive use)"
                    echo "  --json      Output results as JSON"
                    echo ""
                    echo "Available groups:"
                    echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]' | while read -r g; do
                      echo "  $g"
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
                  SKIP_SSM=false
                  SKIP_GH=false
                  FORCE_GH=false

                  while [[ $# -gt 0 ]]; do
                    case "$1" in
                      --ssm-path)
                        SSM_PATH_OVERRIDE="$2"
                        shift 2
                        ;;
                      --no-ssm)
                        SKIP_SSM=true
                        shift
                        ;;
                      --no-gh)
                        SKIP_GH=true
                        shift
                        ;;
                      --force-gh)
                        FORCE_GH=true
                        shift
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

                  KEYS_DIR="${secretsDir}/keys"

                  # Check if group already has a public key configured
                  EXISTING_PUB=$(echo "$GROUPS_JSON" | ${pkgs.jq}/bin/jq -r --arg g "$GROUP_NAME" '.[$g]["age-pub"] // ""')
                  GH_SYNC_ONLY=false
                  if [[ -n "$EXISTING_PUB" ]]; then
                    # If --force-gh is passed without --yes, sync the existing key to
                    # GitHub without regenerating the keypair.
                    if [[ "$FORCE_GH" == "true" && "$FORCE_YES" != "true" ]]; then
                      GH_SYNC_ONLY=true
                      echo "Syncing existing group key to GitHub..." >&2

                      # Resolve the existing private key
                      PLAIN_KEY="$KEYS_DIR/$GROUP_NAME.age"
                      ENC_KEY="$KEYS_DIR/$GROUP_NAME.enc.age"
                      if [[ -f "$PLAIN_KEY" ]]; then
                        PRIVATE_KEY=$(cat "$PLAIN_KEY")
                      elif [[ -f "$ENC_KEY" ]]; then
                        PRIVATE_KEY=$(${pkgs.sops}/bin/sops --decrypt "$ENC_KEY" 2>/dev/null) || {
                          echo "Error: Could not decrypt $ENC_KEY to read the private key." >&2
                          exit 1
                        }
                      else
                        echo "Error: No private key found at $PLAIN_KEY or $ENC_KEY." >&2
                        echo "  Run 'secrets:init-group $GROUP_NAME --yes' to regenerate." >&2
                        exit 1
                      fi

                      PUBLIC_KEY="$EXISTING_PUB"
                      ENC_AGE_FILE="$KEYS_DIR/$GROUP_NAME.enc.age"
                      PLAIN_AGE_FILE="$KEYS_DIR/$GROUP_NAME.age"
                      SOPS_SUCCESS=true
                      SSM_SUCCESS=false
                      if [[ "$JSON_OUTPUT" == "true" ]]; then
                        LOG() { echo "$@" >&2; }
                      else
                        LOG() { echo "$@"; }
                      fi
                    elif [[ "$FORCE_YES" == "true" ]]; then
                      echo "Regenerating keypair (--yes specified)..." >&2
                    else
                      echo "Group '$GROUP_NAME' is already initialized:" >&2
                      echo "  Public key: $EXISTING_PUB" >&2
                      echo "" >&2
                      echo "  To sync existing key to GitHub:  secrets:init-group $GROUP_NAME --force-gh" >&2
                      echo "  To regenerate the keypair:       secrets:init-group $GROUP_NAME --yes" >&2
                      exit 0
                    fi
                  fi

                  if [[ "$GH_SYNC_ONLY" == "true" ]]; then
                    # Skip keypair generation — jump to GH integration below
                    SOPS_SUCCESS=true
                    SSM_SUCCESS=false
                  else

                  echo "Generating AGE keypair for group '$GROUP_NAME'..."

                  # Rename old .age file to preserve history (for decryption of old secrets)
                  OLD_AGE_FILE="$KEYS_DIR/$GROUP_NAME.age"
                  if [[ -f "$OLD_AGE_FILE" ]]; then
                    OLD_PUB=$(${pkgs.age}/bin/age-keygen -y "$OLD_AGE_FILE" 2>/dev/null || true)
                    if [[ -n "$OLD_PUB" ]]; then
                      # Use first 8 and last 8 chars of the public key for the filename
                      PREFIX="''${OLD_PUB:0:8}"
                      SUFFIX="''${OLD_PUB: -8}"
                      ARCHIVE_NAME="$GROUP_NAME-''${PREFIX}-''${SUFFIX}.age"
                      mv "$OLD_AGE_FILE" "$KEYS_DIR/$ARCHIVE_NAME"
                      echo "  Archived old key as keys/$ARCHIVE_NAME"
                    fi
                  fi

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
                  LOG ""

                  if [[ "$DRY_RUN" == "true" ]]; then
                    if [[ "$JSON_OUTPUT" == "true" ]]; then
                      ${pkgs.jq}/bin/jq -n \
                        --arg group "$GROUP_NAME" \
                        --arg publicKey "$PUBLIC_KEY" \
                        --arg ssmPath "$SSM_PATH" \
                        '{group: $group, publicKey: $publicKey, ssmPath: $ssmPath, dryRun: true}'
                    else
                      echo "[DRY RUN] Would encrypt private key to .enc.age file"
                      if [[ "$SKIP_SSM" != "true" ]]; then
                        echo "[DRY RUN] Would store private key at SSM path: $SSM_PATH"
                      fi
                      echo ""
                      echo "To complete setup, add to .stackpanel/config.nix:"
                      echo ""
                      echo "  stackpanel.secrets.groups.$GROUP_NAME.age-pub = \"$PUBLIC_KEY\";"
                      echo ""
                    fi
                    exit 0
                  fi

                  # Store private key as SOPS-encrypted .enc.age file in keys/
                  KEYS_DIR="${secretsDir}/keys"
                  ENC_AGE_FILE="$KEYS_DIR/$GROUP_NAME.enc.age"
                  mkdir -p "$KEYS_DIR"

                  # Write private key to temp file for sops encryption
                  echo "$PRIVATE_KEY" > "$TMPDIR/plain.txt"

                  SOPS_SUCCESS=false
                  if command -v sops &>/dev/null; then
                    # Check if keys/.sops.yaml exists (generated by autoGenerateLocalKeyScript)
                    if [[ -f "$KEYS_DIR/.sops.yaml" ]]; then
                      LOG "Encrypting private key to $ENC_AGE_FILE..."
                      # Use --config to point SOPS to the correct .sops.yaml
                      # Use --filename-override so the path_regex (\.enc\.age$) matches
                      # (input file is in /tmp, so SOPS won't find .sops.yaml or match the regex by default)
                      # Write to temp first, then move (avoids ShellCheck SC2094 read/write same file)
                      if sops --config "$KEYS_DIR/.sops.yaml" --filename-override "$ENC_AGE_FILE" --encrypt --input-type "binary" --output-type "binary" "$TMPDIR/plain.txt" > "$TMPDIR/encrypted.bin" 2>/dev/null; then
                        mv "$TMPDIR/encrypted.bin" "$ENC_AGE_FILE"
                        SOPS_SUCCESS=true
                        LOG "Encrypted group key saved to $ENC_AGE_FILE"
                      else
                        LOG "Warning: SOPS encryption failed. Check keys/.sops.yaml configuration." >&2
                      fi
                    else
                      LOG "Warning: $KEYS_DIR/.sops.yaml not found. Cannot encrypt .enc.age file." >&2
                      LOG "Hint: Re-enter the devshell to auto-generate it, or create it manually." >&2
                    fi
                  else
                    LOG "Warning: sops not found in PATH. Cannot encrypt .enc.age file." >&2
                  fi

                  # Also save plain private key to <group>.age (gitignored, for fast local resolution)
                  PLAIN_AGE_FILE="$KEYS_DIR/$GROUP_NAME.age"
                  cp "$TMPDIR/key.txt" "$PLAIN_AGE_FILE"
                  chmod 600 "$PLAIN_AGE_FILE"
                  LOG "Plain group key saved to $PLAIN_AGE_FILE (gitignored)"

                  # Optionally store in SSM Parameter Store
                  SSM_SUCCESS=false
                  if [[ "$SKIP_SSM" != "true" ]]; then
                    if command -v aws &>/dev/null; then
                      # Check if we have AWS credentials
                      if timeout 3 aws sts get-caller-identity &>/dev/null 2>&1; then
                        LOG "Storing private key in SSM Parameter Store at $SSM_PATH..."
                        CHAMBER_PREFIX="${chamberPrefix}"
                        if command -v chamber &>/dev/null && [[ -n "$CHAMBER_PREFIX" ]]; then
                          aws ssm put-parameter \
                            --name "$SSM_PATH" \
                            --value "$PRIVATE_KEY" \
                            --type SecureString \
                            --overwrite \
                            --description "AGE private key for stackpanel secrets group: $GROUP_NAME" \
                            --tags "Key=Project,Value=${chamberPrefix}" "Key=ManagedBy,Value=stackpanel" \
                            >/dev/null 2>&1 && SSM_SUCCESS=true
                        else
                          aws ssm put-parameter \
                            --name "$SSM_PATH" \
                            --value "$PRIVATE_KEY" \
                            --type SecureString \
                            --overwrite \
                            --description "AGE private key for stackpanel secrets group: $GROUP_NAME" \
                            >/dev/null 2>&1 && SSM_SUCCESS=true
                        fi
                        if [[ "$SSM_SUCCESS" == "true" ]]; then
                          LOG "Stored in SSM at $SSM_PATH"
                        else
                          LOG "Warning: SSM storage failed. The .enc.age file is your primary key storage." >&2
                        fi
                      else
                        LOG "Note: No AWS credentials available. Skipping SSM storage."
                        LOG "      The .enc.age file is your primary key storage."
                      fi
                    else
                      LOG "Note: AWS CLI not available. Skipping SSM storage."
                      LOG "      The .enc.age file is your primary key storage."
                    fi
                  fi

                  if [[ "$SOPS_SUCCESS" != "true" && "$SSM_SUCCESS" != "true" ]]; then
                    echo "Error: Could not store the private key in any backend." >&2
                    echo "Ensure either:" >&2
                    echo "  - SOPS is available and keys/.sops.yaml is configured" >&2
                    echo "  - AWS credentials are available for SSM storage" >&2
                    exit 1
                  fi

                  fi  # end of GH_SYNC_ONLY guard

                  # ── GitHub Actions integration ───────────────────────────────────────
                  # Upload the group private key as a GitHub Actions secret so the
                  # rekey workflow can decrypt and re-encrypt .enc.age files when
                  # new recipients are added.
                  GH_SUCCESS=false
                  WORKFLOW_GENERATED=false
                  RECIPIENTS_DIR="${secretsDir}/keys/recipients"

                  if [[ "$SKIP_GH" == "true" ]]; then
                    LOG "Skipping GitHub integration (--no-gh)."
                  elif command -v gh &>/dev/null; then
                    # Check if we're in a GitHub repo with auth
                    if gh auth status &>/dev/null 2>&1; then
                      # Upload private key as a GitHub secret
                      GH_SECRET_NAME="SECRETS_AGE_KEY_$(echo "$GROUP_NAME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

                      # Check if the secret already exists to avoid overwriting
                      # (overwriting would break the rekey workflow if the .enc.age
                      # files are still encrypted with the old key).
                      SECRET_EXISTS=false
                      if gh secret list 2>/dev/null | grep -q "^$GH_SECRET_NAME"; then
                        SECRET_EXISTS=true
                      fi

                      if [[ "$SECRET_EXISTS" == "true" && "$FORCE_GH" != "true" ]]; then
                        LOG "GitHub secret $GH_SECRET_NAME already exists. Skipping upload."
                        LOG "  Use --force-gh to overwrite."
                        GH_SUCCESS=true  # treat as success since the secret is already there
                      else
                        if [[ "$SECRET_EXISTS" == "true" ]]; then
                          LOG "Overwriting existing GitHub secret $GH_SECRET_NAME (--force-gh)..."
                        else
                          LOG "Uploading group private key as GitHub Actions secret: $GH_SECRET_NAME..."
                        fi
                        if echo "$PRIVATE_KEY" | gh secret set "$GH_SECRET_NAME" 2>/dev/null; then
                          GH_SUCCESS=true
                          LOG "Stored as GitHub secret: $GH_SECRET_NAME"
                        else
                          LOG "Warning: Failed to upload GitHub secret. You can do this manually:" >&2
                          LOG "  gh secret set $GH_SECRET_NAME < <(sops --decrypt $ENC_AGE_FILE)" >&2
                        fi
                      fi

                      # Generate / update the rekey workflow.
                      # Always regenerated so the env: block includes all known groups.
                      WORKFLOW_DIR=".github/workflows"
                      WORKFLOW_FILE="$WORKFLOW_DIR/secrets-rekey.yml"
                      LOG "Generating GitHub Actions rekey workflow..."
                      mkdir -p "$WORKFLOW_DIR"

                      # ── Build dynamic env: block ──────────────────────────────────
                      # Maps GH secrets -> env vars for each known group.
                      # Each line: "          SECRET_DEV: GHA-secrets-expression"
                      ENV_LINES=""
                      for enc_file in "$KEYS_DIR"/*.enc.age; do
                        [[ -f "$enc_file" ]] || continue
                        GRP=$(basename "$enc_file" .enc.age)
                        GRP_UPPER=$(echo "$GRP" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                        ENV_LINES="''${ENV_LINES}          SECRET_''${GRP_UPPER}: \''${{ secrets.SECRETS_AGE_KEY_''${GRP_UPPER} }}
      "
                      done
                      # Include current group if .enc.age not yet written
                      CURRENT_UPPER=$(echo "$GROUP_NAME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                      if ! echo "$ENV_LINES" | grep -q "SECRET_$CURRENT_UPPER"; then
                        ENV_LINES="''${ENV_LINES}          SECRET_''${CURRENT_UPPER}: \''${{ secrets.SECRETS_AGE_KEY_''${CURRENT_UPPER} }}
      "
                      fi

                      # ── Write workflow from template ─────────────────────────────
                      # The workflow YAML template lives in a separate file to avoid
                      # Nix/bash/YAML escaping issues. We copy it and inject the
                      # dynamic env: block (one SECRET_<GROUP> per known group).
                      TEMPLATE="${rekeyWorkflowTemplate}"
                      cp "$TEMPLATE" "$WORKFLOW_FILE"

                      # Replace the __ENV_BLOCK__ placeholder with the actual env
                      # mappings. Use a temp file to avoid read/write on same file.
                      # The placeholder is on its own line; we replace it with
                      # properly-indented YAML key-value pairs.
                      {
                        while IFS= read -r line; do
                          if [[ "$line" == *"__ENV_BLOCK__"* ]]; then
                            printf '%s' "$ENV_LINES"
                          else
                            printf '%s\n' "$line"
                          fi
                        done < "$WORKFLOW_FILE"
                      } > "''${WORKFLOW_FILE}.tmp" && mv "''${WORKFLOW_FILE}.tmp" "$WORKFLOW_FILE"

                      WORKFLOW_GENERATED=true
                      LOG "Generated $WORKFLOW_FILE"
                    else
                      LOG "Note: GitHub CLI not authenticated. Skipping GitHub integration."
                      LOG "      Run 'gh auth login' then re-run to enable CI-based rekeying."
                    fi
                  else
                    LOG "Note: GitHub CLI (gh) not available. Skipping GitHub integration."
                    LOG "      Install gh and re-run to enable CI-based rekeying."
                  fi

                  if [[ "$JSON_OUTPUT" == "true" ]]; then
                    # Output clean JSON to stdout for machine consumption
                    ${pkgs.jq}/bin/jq -n \
                      --arg group "$GROUP_NAME" \
                      --arg publicKey "$PUBLIC_KEY" \
                      --arg ssmPath "$SSM_PATH" \
                      --arg encAgePath "$ENC_AGE_FILE" \
                      --argjson sopsStored "$SOPS_SUCCESS" \
                      --argjson ssmStored "$SSM_SUCCESS" \
                      --argjson ghStored "$GH_SUCCESS" \
                      --argjson workflowGenerated "$WORKFLOW_GENERATED" \
                      '{group: $group, publicKey: $publicKey, ssmPath: $ssmPath, encAgePath: $encAgePath, sopsStored: $sopsStored, ssmStored: $ssmStored, ghStored: $ghStored, workflowGenerated: $workflowGenerated, dryRun: false, success: true}'
                  else
                    echo ""
                    echo "Done! Private key stored in:"
                    if [[ "$SOPS_SUCCESS" == "true" ]]; then
                      echo "  - $ENC_AGE_FILE (SOPS-encrypted, check into git)"
                    fi
                    if [[ "$SSM_SUCCESS" == "true" ]]; then
                      echo "  - $SSM_PATH (SSM Parameter Store)"
                    fi
                    if [[ "$GH_SUCCESS" == "true" ]]; then
                      echo "  - GitHub Actions secret: $GH_SECRET_NAME"
                    fi
                    echo ""
                    if [[ "$WORKFLOW_GENERATED" == "true" ]]; then
                      echo "  Rekey workflow generated at .github/workflows/secrets-rekey.yml"
                      echo ""
                      echo "  Team onboarding flow:"
                      echo "    1. New member enters devshell (auto-generates key)"
                      echo "    2. Their pub key is saved to $RECIPIENTS_DIR/<name>.pub"
                      echo "    3. They commit + push the .pub file"
                      echo "    4. The rekey workflow re-encrypts .enc.age files"
                      echo "    5. They pull and can now decrypt secrets"
                      echo ""
                    fi
                    echo "Next steps:"
                    echo "  1. Add the public key to .stackpanel/config.nix (or data/secrets.nix):"
                    echo ""
                    echo "     stackpanel.secrets.groups.$GROUP_NAME.age-pub = \"$PUBLIC_KEY\";"
                    echo ""
                    if [[ "$SOPS_SUCCESS" == "true" ]]; then
                      echo "  2. Commit the .enc.age file: git add $ENC_AGE_FILE"
                      if [[ "$WORKFLOW_GENERATED" == "true" ]]; then
                        echo "  3. Commit the workflow: git add .github/workflows/secrets-rekey.yml"
                        echo "  4. Push and restart devshell"
                      else
                        echo "  3. Restart devshell to pick up the change"
                      fi
                    else
                      echo "  2. Restart devshell to pick up the change"
                    fi
                    echo ""
                  fi
    '';

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
