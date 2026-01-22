# ==============================================================================
# combined.nix
#
# Combined secrets generation for app environments.
#
# With the master key model, this module:
# - Collects all SECRET variables for an app/environment
# - Decrypts them using available master keys
# - Outputs combined env files for runtime use
# ==============================================================================
{
  config,
  lib,
  pkgs,
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

  # Script to export secrets as environment variables
  exportSecretsScript = pkgs.writeShellApplication {
    name = "export-secrets";
    runtimeInputs = [ pkgs.age pkgs.jq pkgs.vals ];
    text = ''
      ${secretsLib.tryDecryptScript}

      SECRETS_DIR="${cfg.secrets-dir}"
      MASTER_KEYS_JSON='${builtins.toJSON masterKeysConfig}'

      usage() {
        echo "Usage: export-secrets [--format env|json|yaml]"
        echo ""
        echo "Decrypt and export all secrets."
        exit 1
      }

      FORMAT="env"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --format)
            FORMAT="$2"
            shift 2
            ;;
          *)
            usage
            ;;
        esac
      done

      # Build decrypt args
      DECRYPT_ARGS=()
      for KEY_NAME in $(echo "$MASTER_KEYS_JSON" | jq -r 'keys[]'); do
        REF=$(echo "$MASTER_KEYS_JSON" | jq -r --arg k "$KEY_NAME" '.[$k].ref')
        RESOLVE_CMD=$(echo "$MASTER_KEYS_JSON" | jq -r --arg k "$KEY_NAME" '.[$k]["resolve-cmd"] // ""')
        DECRYPT_ARGS+=("$KEY_NAME" "$REF" "$RESOLVE_CMD")
      done

      # Process each .age file
      declare -A SECRETS

      for AGE_FILE in "$SECRETS_DIR"/*.age 2>/dev/null; do
        [[ -f "$AGE_FILE" ]] || continue

        BASENAME=$(basename "$AGE_FILE" .age)
        
        # Try to decrypt
        VALUE=$(try_decrypt "$AGE_FILE" "''${DECRYPT_ARGS[@]}" 2>/dev/null) || {
          echo "# Warning: Could not decrypt $BASENAME" >&2
          continue
        }

        # Convert filename to env var name (uppercase, underscores)
        KEY=$(echo "$BASENAME" | tr '[:lower:]-' '[:upper:]_')
        SECRETS["$KEY"]="$VALUE"
      done

      case "$FORMAT" in
        env)
          for KEY in "''${!SECRETS[@]}"; do
            VALUE="''${SECRETS[$KEY]}"
            echo "export $KEY='$VALUE'"
          done
          ;;
        json)
          echo "{"
          FIRST=true
          for KEY in "''${!SECRETS[@]}"; do
            if [[ "$FIRST" != "true" ]]; then echo ","; fi
            FIRST=false
            VALUE="''${SECRETS[$KEY]}"
            printf '  "%s": "%s"' "$KEY" "$VALUE"
          done
          echo ""
          echo "}"
          ;;
        yaml)
          for KEY in "''${!SECRETS[@]}"; do
            VALUE="''${SECRETS[$KEY]}"
            echo "$KEY: \"$VALUE\""
          done
          ;;
        *)
          echo "Unknown format: $FORMAT" >&2
          exit 1
          ;;
      esac
    '';
  };

in
{
  config = lib.mkIf cfg.enable {
    stackpanel.scripts = {
      "secrets:export" = {
        exec = "${exportSecretsScript}/bin/export-secrets \"$@\"";
        description = "Decrypt and export all secrets (--format env|json|yaml)";
      };

      "secrets:env" = {
        exec = ''
          # Source secrets into current shell
          eval "$(${exportSecretsScript}/bin/export-secrets --format env)"
          echo "✅ Secrets loaded into environment"
        '';
        description = "Load all secrets into current shell environment";
      };
    };
  };
}
