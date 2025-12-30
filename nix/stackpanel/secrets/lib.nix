# ==============================================================================
# lib.nix
#
# Shared library functions for the secrets module.
# Contains reusable script logic for both devenv and standalone adapters.
#
# Functions provided:
# - toJsonScript: Shell function to decrypt SOPS YAML to JSON
# - ensureAgeKeyScript: Validates AGE key existence and correctness
# - sopsWrapperScript: Wrapped SOPS with preflight key validation
# - generateSecretsSchemaScript: Generates typed code from secrets
# - generateSecretsPackageScript: Full codegen orchestration
#
# This library is imported by both default.nix (standalone packages) and
# core.nix (devenv scripts) to ensure consistent behavior.
# ==============================================================================
{ lib, pkgs }:
rec {
  # Convert YAML file to JSON (decrypting with SOPS)
  # Returns a shell function that can be used in scripts
  toJsonScript = ''
    to_json() {
      cat "$1" \
        | ${pkgs.yq}/bin/yq \
        | ${pkgs.sops}/bin/sops decrypt --input-type json --output-type json /dev/stdin
    }
  '';

  # Build the ensure-age-key script body
  ensureAgeKeyScript = ''
    KEYFILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

    if [[ ! -f "$KEYFILE" ]]; then
      echo "❌ Error: AGE key file not found at $KEYFILE" >&2
      echo "Follow the instructions to add the decryption key:" >&2
      echo "1. Find 'SOPS (Dev)' in 1Password > Dev Vault" >&2
      echo "2. Copy the AGE secret key (password)" >&2
      echo "3. Add it to $KEYFILE (create the file if it doesn't exist)" >&2
      echo "4. Try again" >&2
      exit 1
    fi

    while read -r line; do
      [[ "$line" == AGE-SECRET-KEY-* ]] || continue
      derived="$(printf '%s\n' "$line" | ${pkgs.age}/bin/age-keygen -y - | awk '{print $NF}')"
      if [[ "$derived" == "$AGE_PUBLIC_KEY_DEV" ]]; then
        [[ "$1" != "-q" ]] && echo "✅ Dev age key found in $KEYFILE"
        exit 0
      fi
    done < "$KEYFILE"

    echo "❌ Error: Dev age key not found in $KEYFILE" >&2
    echo "Follow the instructions to add the decryption key:" >&2
    echo "1. Find 'SOPS (Dev)' in 1Password > Dev Vault" >&2
    echo "2. Copy the AGE secret key (password)" >&2
    echo "3. Add it to $KEYFILE (create the file if it doesn't exist)" >&2
    echo "4. Try again" >&2
    exit 1
  '';

  # Build the sops wrapper script body (takes ensure-age-key path as arg)
  sopsWrapperScript = ensureAgeKeyPath: ''
    # Run preflight check before sops
    ${ensureAgeKeyPath} -q || exit 1
    export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    exec ${pkgs.sops}/bin/sops "$@"
  '';

  # Build generate-secrets-schema script body
  generateSecretsSchemaScript = ''
    set -e
    ${toJsonScript}

    INPUT_FILE="$1"
    OUTPUT_FILE="$2"
    LANGUAGE="$3"
    JSON_DATA=$(to_json "$INPUT_FILE")

    case "$LANGUAGE" in
      "typescript")
        echo "$JSON_DATA" | ${pkgs.bun}/bin/bun x quicktype -o "$OUTPUT_FILE" --lang typescript -
        ;;
      "go")
        echo "$JSON_DATA" | ${pkgs.bun}/bin/bun x quicktype -o "$OUTPUT_FILE" --lang go -
        ;;
      *)
        echo "Unsupported language: $LANGUAGE" >&2
        exit 1
        ;;
    esac
  '';

  # Build generate-secrets-package script body
  # Takes cfg values as arguments to bake in at build time
  generateSecretsPackageScript =
    {
      inputDir,
      environments,
      codegen,
    }:
    ''
      set -e
      ${toJsonScript}

      INPUT_DIR="${inputDir}"

      # Configuration baked in at build time as JSON
      ENVIRONMENTS_JSON='${builtins.toJSON environments}'
      CODEGEN_JSON='${builtins.toJSON codegen}'

      for ENV_NAME in $(echo "$ENVIRONMENTS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
        ENV_CFG=$(echo "$ENVIRONMENTS_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$ENV_NAME" '.[$name]')
        SOURCES=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r '.sources[]')

        # Decrypt and merge all source files for this environment
        MERGED_SECRETS=$(mktemp)
        {
          for SRC in $SOURCES; do
            to_json "$INPUT_DIR/$SRC.yaml"
          done
        } | ${pkgs.jq}/bin/jq -s 'reduce .[] as $item ({}; . * $item)' > "$MERGED_SECRETS"

        # Generate code for each codegen target
        for CODEGEN_NAME in $(echo "$CODEGEN_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
          CODEGEN_CFG=$(echo "$CODEGEN_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$CODEGEN_NAME" '.[$name]')
          OUTPUT_DIR=$(echo "$CODEGEN_CFG" | ${pkgs.jq}/bin/jq -r '.directory')
          LANGUAGE=$(echo "$CODEGEN_CFG" | ${pkgs.jq}/bin/jq -r '.language')
          mkdir -p "$OUTPUT_DIR"
          OUTPUT_FILE="$OUTPUT_DIR/''${ENV_NAME}_secrets.$( [ "$LANGUAGE" = "typescript" ] && echo "ts" || echo "go" )"
          generate-secrets-schema "$MERGED_SECRETS" "$OUTPUT_FILE" "$LANGUAGE"
          echo "Generated secrets for environment '$ENV_NAME' in '$OUTPUT_FILE'"
        done

        rm "$MERGED_SECRETS"
      done
    '';
}
