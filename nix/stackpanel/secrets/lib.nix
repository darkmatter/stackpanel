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
{
  lib,
  pkgs,
  ageKeyFiles ? [
    "\${SOPS_AGE_KEY_FILE:-}"
    "\${HOME}/.config/sops/age/keys.txt"
    "\${HOME}/.age/keys.txt"
    "\${HOME}/.config/age/keys.txt"
    "/etc/sops/age/keys.txt"
  ],
}:
let
  # Convert age key files list to bash array string
  ageKeyLocationsArray = lib.concatMapStringsSep "\n      " (loc: ''"${loc}"'') ageKeyFiles;
in
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

  # Script to auto-generate an AGE key if none exists (for bootstrap)
  # Returns 0 if key exists or was created, 1 on failure
  autoGenerateAgeKeyScript = ''
    STATE_DIR=".stackpanel/state"
    KEY_FILE="$STATE_DIR/age-key.txt"
    IDENTITY_FILE="$STATE_DIR/age-identity"
    
    # Check if we already have a key configured
    if [[ -f "$IDENTITY_FILE" ]]; then
      exit 0
    fi
    
    # Check default locations
    for loc in "''${SOPS_AGE_KEY_FILE:-}" "$HOME/.config/sops/age/keys.txt" "$HOME/.age/keys.txt" "$HOME/.config/age/keys.txt"; do
      [[ -z "$loc" ]] && continue
      if [[ -f "$loc" ]]; then
        exit 0
      fi
    done
    
    # No key found - auto-generate one
    echo "🔐 No AGE key found. Generating a new one for local development..." >&2
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    
    # Generate new AGE key
    ${pkgs.age}/bin/age-keygen -o "$KEY_FILE" 2>/dev/null
    chmod 600 "$KEY_FILE"
    
    # Store marker in identity file
    echo "AGE-SECRET-KEY-..." > "$IDENTITY_FILE"
    chmod 600 "$IDENTITY_FILE"
    
    # Extract public key
    PUBLIC_KEY=$(${pkgs.age}/bin/age-keygen -y "$KEY_FILE" 2>/dev/null)
    
    echo "✅ Generated new AGE key:" >&2
    echo "   Private key: $KEY_FILE" >&2
    echo "   Public key:  $PUBLIC_KEY" >&2
    echo "" >&2
    echo "⚠️  This key is local to your machine. Add it to .sops.yaml to encrypt secrets." >&2
    echo "   Or configure a team-wide key in the Stackpanel UI." >&2
  '';

  # Build the ensure-age-key script body
  ensureAgeKeyScript = ''
    # Check configured locations for AGE key file
    AGE_KEY_LOCATIONS=(
      ${ageKeyLocationsArray}
    )

    KEYFILE=""
    for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
      [[ -z "$loc" ]] && continue
      if [[ -f "$loc" ]]; then
        KEYFILE="$loc"
        break
      fi
    done

    # Also check .stackpanel/state/age-key.txt
    STATE_KEY=".stackpanel/state/age-key.txt"
    if [[ -z "$KEYFILE" ]] && [[ -f "$STATE_KEY" ]]; then
      KEYFILE="$STATE_KEY"
    fi

    if [[ -z "$KEYFILE" ]]; then
      echo "❌ Error: AGE key file not found in any of these locations:" >&2
      for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
        [[ -n "$loc" ]] && echo "  - $loc" >&2
      done
      echo "  - $STATE_KEY" >&2
      echo "" >&2
      echo "To create a new key, run: age-keygen -o ~/.config/sops/age/keys.txt" >&2
      echo "Or set SOPS_AGE_KEY_FILE to point to your existing key." >&2
      exit 1
    fi

    # Validate the key file contains at least one valid AGE secret key
    FOUND_KEY=false
    while read -r line; do
      if [[ "$line" == AGE-SECRET-KEY-* ]]; then
        FOUND_KEY=true
        # Derive and display the public key
        PUBLIC_KEY="$(printf '%s\n' "$line" | ${pkgs.age}/bin/age-keygen -y - 2>/dev/null | awk '{print $NF}')"
        if [[ -n "$PUBLIC_KEY" ]]; then
          [[ "$1" != "-q" ]] && echo "✅ AGE key found in $KEYFILE"
          [[ "$1" != "-q" ]] && echo "   Public key: $PUBLIC_KEY"
          exit 0
        fi
      fi
    done < "$KEYFILE"

    if [[ "$FOUND_KEY" == "false" ]]; then
      echo "❌ Error: No valid AGE secret key found in $KEYFILE" >&2
      echo "The file should contain a line starting with AGE-SECRET-KEY-" >&2
      exit 1
    fi
  '';

  # Build the sops wrapper script body (takes ensure-age-key path as arg)
  sopsWrapperScript = ensureAgeKeyPath: ''
    STATE_DIR=".stackpanel/state"
    IDENTITY_FILE="$STATE_DIR/age-identity"
    KEY_FILE="$STATE_DIR/age-key.txt"
    
    # Find identity - priority: state file > env var > defaults
    find_identity() {
      # 1. Check state file
      if [[ -f "$IDENTITY_FILE" ]]; then
        IDENTITY_VALUE=$(cat "$IDENTITY_FILE")
        if [[ "$IDENTITY_VALUE" == AGE-SECRET-KEY-* ]] || [[ "$IDENTITY_VALUE" == "-----BEGIN"* ]]; then
          # Key content is stored in separate file
          if [[ -f "$KEY_FILE" ]]; then
            echo "$KEY_FILE"
            return 0
          fi
        else
          # It's a path - expand ~
          EXPANDED="$IDENTITY_VALUE"
          if [[ "$IDENTITY_VALUE" == "~"* ]]; then
            EXPANDED="$HOME''${IDENTITY_VALUE:1}"
          fi
          if [[ -f "$EXPANDED" ]]; then
            echo "$EXPANDED"
            return 0
          fi
        fi
      fi
      
      # 2. Check SOPS_AGE_KEY_FILE env var
      if [[ -n "''${SOPS_AGE_KEY_FILE:-}" ]] && [[ -f "$SOPS_AGE_KEY_FILE" ]]; then
        echo "$SOPS_AGE_KEY_FILE"
        return 0
      fi
      
      # 3. Check default locations
      for loc in "$HOME/.config/sops/age/keys.txt" "$HOME/.age/keys.txt" "$HOME/.config/age/keys.txt"; do
        if [[ -f "$loc" ]]; then
          echo "$loc"
          return 0
        fi
      done
      
      return 1
    }
    
    # Interactive prompt for missing key
    prompt_for_key() {
      echo "🔐 No AGE/SSH private key found for SOPS decryption." >&2
      echo "" >&2
      echo "You can provide:" >&2
      echo "  1. A path to your private key (e.g., ~/.ssh/id_ed25519)" >&2
      echo "  2. The key content directly (AGE-SECRET-KEY-...)" >&2
      echo "" >&2
      read -rp "Enter path or key: " USER_INPUT
      
      if [[ -z "$USER_INPUT" ]]; then
        echo "❌ No input provided" >&2
        exit 1
      fi
      
      # Create state dir if needed
      mkdir -p "$STATE_DIR"
      chmod 700 "$STATE_DIR"
      
      if [[ "$USER_INPUT" == AGE-SECRET-KEY-* ]] || [[ "$USER_INPUT" == "-----BEGIN"* ]]; then
        # Store key content
        echo "$USER_INPUT" > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
        echo "AGE-SECRET-KEY-..." > "$IDENTITY_FILE"
        chmod 600 "$IDENTITY_FILE"
        echo "✅ Key stored in $KEY_FILE" >&2
        echo "$KEY_FILE"
      else
        # Store path
        EXPANDED="$USER_INPUT"
        if [[ "$USER_INPUT" == "~"* ]]; then
          EXPANDED="$HOME''${USER_INPUT:1}"
        fi
        if [[ ! -f "$EXPANDED" ]]; then
          echo "❌ File not found: $EXPANDED" >&2
          exit 1
        fi
        echo "$USER_INPUT" > "$IDENTITY_FILE"
        chmod 600 "$IDENTITY_FILE"
        echo "✅ Path stored: $USER_INPUT" >&2
        echo "$EXPANDED"
      fi
    }
    
    # Check if identity is configured in state directory
    if [[ ! -f "$IDENTITY_FILE" ]]; then
      echo "⚠️  No decryption key configured in .stackpanel/state/" >&2
      echo "   Configure your key in the Stackpanel UI: /studio/variables" >&2
      echo "   Or run this command interactively to set it up now." >&2
      echo "" >&2
    fi
    
    # Find or prompt for key
    KEY_PATH=$(find_identity)
    if [[ -z "$KEY_PATH" ]]; then
      # Only prompt if interactive
      if [[ -t 0 ]]; then
        KEY_PATH=$(prompt_for_key)
      else
        echo "❌ No AGE key configured. Configure via the Stackpanel UI at /studio/variables" >&2
        exit 1
      fi
    fi
    
    # Check if it's an SSH key or AGE key
    if [[ -f "$KEY_PATH" ]]; then
      FIRST_LINE=$(head -n1 "$KEY_PATH" 2>/dev/null || echo "")
      if [[ "$FIRST_LINE" == "-----BEGIN"* ]] || [[ "$KEY_PATH" == *".ssh/"* ]] || [[ "$KEY_PATH" == *"id_"* ]]; then
        # SSH key - use SOPS_AGE_SSH_PRIVATE_KEY_FILE
        export SOPS_AGE_SSH_PRIVATE_KEY_FILE="$KEY_PATH"
      else
        # AGE key - use SOPS_AGE_KEY_FILE
        export SOPS_AGE_KEY_FILE="$KEY_PATH"
      fi
    else
      export SOPS_AGE_KEY_FILE="$KEY_PATH"
    fi
    
    exec ${pkgs.sops}/bin/sops "$@"
  '';

  # Build generate-secrets-schema script body
  # Generates znv-based TypeScript or Go code from YAML/JSON env files.
  # INPUT_FILE can be either:
  #   - A .json file (read directly)
  #   - A .yaml file (try to decrypt with SOPS, fallback to plain YAML)
  generateSecretsSchemaScript = ''
    set -e

    INPUT_FILE="$1"
    OUTPUT_FILE="$2"
    LANGUAGE="$3"
    
    # Determine how to read the input
    case "$INPUT_FILE" in
      *.json)
        # Plain JSON file - read directly
        JSON_DATA=$(cat "$INPUT_FILE")
        ;;
      *.yaml|*.yml)
        # YAML file - try SOPS decrypt, fallback to plain conversion
        if ${pkgs.sops}/bin/sops -d "$INPUT_FILE" 2>/dev/null | ${pkgs.yq-go}/bin/yq -o json > /tmp/secrets_temp.json; then
          JSON_DATA=$(cat /tmp/secrets_temp.json)
        else
          # Not SOPS-encrypted, just convert YAML to JSON
          JSON_DATA=$(${pkgs.yq-go}/bin/yq -o json "$INPUT_FILE")
        fi
        ;;
      *)
        # Try to read as JSON, fallback to YAML
        if JSON_DATA=$(cat "$INPUT_FILE" | ${pkgs.jq}/bin/jq . 2>/dev/null); then
          : # Already valid JSON
        else
          JSON_DATA=$(${pkgs.yq-go}/bin/yq -o json "$INPUT_FILE")
        fi
        ;;
    esac

    case "$LANGUAGE" in
      "typescript")
        # Generate znv-based TypeScript that auto-parses from process.env
        # Extract keys from JSON and generate zod schema
        KEYS=$(echo "$JSON_DATA" | ${pkgs.jq}/bin/jq -r 'keys[]')
        
        cat > "$OUTPUT_FILE" << 'HEADER'
// Auto-generated by Stackpanel - do not edit manually
// Run 'secrets:generate' to regenerate from your app configuration
import { parseEnv, z } from "znv";

HEADER
        
        # Build the schema object
        echo "export const env = parseEnv(process.env, {" >> "$OUTPUT_FILE"
        
        for KEY in $KEYS; do
          # Get the value to infer type
          VALUE=$(echo "$JSON_DATA" | ${pkgs.jq}/bin/jq -r --arg k "$KEY" '.[$k]')
          
          # Infer Zod type from value
          if [[ "$VALUE" =~ ^[0-9]+$ ]]; then
            # Numeric value - use coerce.number()
            echo "  $KEY: z.coerce.number()," >> "$OUTPUT_FILE"
          elif [[ "$VALUE" == "true" ]] || [[ "$VALUE" == "false" ]]; then
            # Boolean value
            echo "  $KEY: z.coerce.boolean()," >> "$OUTPUT_FILE"
          else
            # Default to string
            echo "  $KEY: z.string()," >> "$OUTPUT_FILE"
          fi
        done
        
        echo "});" >> "$OUTPUT_FILE"
        ;;
      "go")
        # Generate Go struct with env tags
        KEYS=$(echo "$JSON_DATA" | ${pkgs.jq}/bin/jq -r 'keys[]')
        
        cat > "$OUTPUT_FILE" << 'HEADER'
// Auto-generated by Stackpanel - do not edit manually
// Run 'secrets:generate' to regenerate from your app configuration
package env

import "os"

type Config struct {
HEADER
        
        for KEY in $KEYS; do
          VALUE=$(echo "$JSON_DATA" | ${pkgs.jq}/bin/jq -r --arg k "$KEY" '.[$k]')
          
          # Infer Go type from value
          if [[ "$VALUE" =~ ^[0-9]+$ ]]; then
            echo "	$KEY string \`env:\"$KEY\"\`" >> "$OUTPUT_FILE"
          else
            echo "	$KEY string \`env:\"$KEY\"\`" >> "$OUTPUT_FILE"
          fi
        done
        
        cat >> "$OUTPUT_FILE" << 'FOOTER'
}

func Load() Config {
	return Config{
FOOTER
        
        for KEY in $KEYS; do
          echo "		$KEY: os.Getenv(\"$KEY\")," >> "$OUTPUT_FILE"
        done
        
        echo "	}" >> "$OUTPUT_FILE"
        echo "}" >> "$OUTPUT_FILE"
        ;;
      *)
        echo "Unsupported language: $LANGUAGE" >&2
        exit 1
        ;;
    esac
  '';

  # Build generate-secrets-package script body
  # Generates TypeScript/Go types from the YAML files in packages/env/data/.
  # No Nix evaluation needed - just reads the YAML files generated by generate-sops-secrets.
  generateSecretsPackageScript =
    {
      inputDir,
      environments,
      codegen,
    }:
    ''
      set -e

      DATA_DIR="packages/env/data"
      SRC_DIR="packages/env/src/generated"
      CODEGEN_JSON='${builtins.toJSON codegen}'

      # Check if codegen is configured
      if [[ "$CODEGEN_JSON" == "{}" ]] || [[ -z "$CODEGEN_JSON" ]]; then
        echo "ℹ️  No codegen configured, skipping package generation"
        exit 0
      fi

      echo "📦 Generating typed env package from YAML..."

      # Check if data directory exists
      if [[ ! -d "$DATA_DIR" ]]; then
        echo "⚠️  No data directory found at $DATA_DIR"
        echo "   Run generate-sops-secrets first to create YAML files."
        exit 0
      fi

      # Create src directory
      mkdir -p "$SRC_DIR"

      # Process each app directory
      for APP_DIR in "$DATA_DIR"/*/; do
        [[ ! -d "$APP_DIR" ]] && continue
        APP_NAME=$(basename "$APP_DIR")

        # Create app directory in src
        mkdir -p "$SRC_DIR/$APP_NAME"

        # Process each environment YAML
        for YAML_FILE in "$APP_DIR"*.yaml; do
          [[ ! -f "$YAML_FILE" ]] && continue
          
          ENV_NAME=$(basename "$YAML_FILE" .yaml)
          
          # Generate TypeScript from YAML
          for CODEGEN_NAME in $(echo "$CODEGEN_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
            CODEGEN_CFG=$(echo "$CODEGEN_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$CODEGEN_NAME" '.[$name]')
            LANGUAGE=$(echo "$CODEGEN_CFG" | ${pkgs.jq}/bin/jq -r '.language')
            
            # Normalize language name
            case "$LANGUAGE" in
              "CODEGEN_LANGUAGE_TYPESCRIPT"|"typescript") LANG="typescript"; EXT="ts" ;;
              "CODEGEN_LANGUAGE_GO"|"go") LANG="go"; EXT="go" ;;
              *) LANG="typescript"; EXT="ts" ;;
            esac
            
            OUTPUT_FILE="$SRC_DIR/$APP_NAME/''${ENV_NAME}.$EXT"
            generate-secrets-schema "$YAML_FILE" "$OUTPUT_FILE" "$LANG"
            echo "   ✅ $OUTPUT_FILE"
          done
        done

        # Create barrel export for this app
        INDEX_FILE="$SRC_DIR/$APP_NAME/index.ts"
        echo "// Auto-generated barrel export - do not edit" > "$INDEX_FILE"
        for TS_FILE in "$SRC_DIR/$APP_NAME"/*.ts; do
          [[ ! -f "$TS_FILE" ]] && continue
          [[ "$(basename "$TS_FILE")" == "index.ts" ]] && continue
          MODULE_NAME=$(basename "$TS_FILE" .ts)
          echo "export * from './$MODULE_NAME';" >> "$INDEX_FILE"
        done
      done
      
      # Create root index.ts for generated types
      ROOT_INDEX="$SRC_DIR/index.ts"
      echo "// Auto-generated barrel export - do not edit" > "$ROOT_INDEX"
      for APP_DIR in "$SRC_DIR"/*/; do
        [[ ! -d "$APP_DIR" ]] && continue
        APP_NAME=$(basename "$APP_DIR")
        echo "export * as $APP_NAME from './$APP_NAME';" >> "$ROOT_INDEX"
      done
      echo "   ✅ $ROOT_INDEX"
      
      echo "✅ Env package generation complete!"
    '';

  # Build generate-sops-secrets script body
  # Generates SOPS YAML files from apps.nix and evaluated variables.
  # Writes to packages/env/data/<app>/<env>.yaml with ALL variables (not just secrets).
  # These files are then used by generate-secrets-package to create TypeScript types.
  generateSopsSecretsScript =
    {
      secretsDir,      # .stackpanel/secrets (for .age files)
      dataDir,         # .stackpanel/data
      ageIdentityFile, # Path to AGE/SSH private key for decryption
    }:
    ''
      set -e

      SECRETS_DIR="${secretsDir}"
      DATA_DIR="${dataDir}"
      VARS_DIR="$SECRETS_DIR/vars"
      KEYS_DIR="$SECRETS_DIR/keys"
      AGE_IDENTITY="${ageIdentityFile}"
      OUTPUT_DIR="packages/env/data"  # Where to write the YAML files
      MASTER_KEY_ENC="$KEYS_DIR/master.key.age"
      MASTER_KEY_DECRYPTED=""
      USING_MASTER_KEY=false

      # Check if age identity exists
      if [[ -n "$AGE_IDENTITY" && ! -f "$AGE_IDENTITY" ]]; then
        echo "❌ Error: AGE identity file not found: $AGE_IDENTITY" >&2
        echo "Set a valid path or leave empty for default locations." >&2
        exit 1
      fi

      # Find user identity for decrypting master key (or secrets directly if no master)
      USER_IDENTITIES=()
      for loc in .stackpanel/state/age-key.txt ~/.config/sops/age/keys.txt ~/.config/age/key.txt ~/.age/key.txt ~/.ssh/id_ed25519 ~/.ssh/id_rsa; do
        [[ -f "$loc" ]] && USER_IDENTITIES+=("$loc")
      done
      [[ -n "$AGE_IDENTITY" ]] && USER_IDENTITIES=("$AGE_IDENTITY" "''${USER_IDENTITIES[@]}")

      # Try to decrypt master key if it exists (envelope encryption mode)
      if [[ -f "$MASTER_KEY_ENC" ]]; then
        echo "🔑 Master key detected, using envelope encryption..."
        MASTER_KEY_DECRYPTED=$(mktemp)
        # shellcheck disable=SC2064
        trap "rm -f '$MASTER_KEY_DECRYPTED'" EXIT

        MASTER_DECRYPTED=false
        for IDENTITY in "''${USER_IDENTITIES[@]}"; do
          if ${pkgs.age}/bin/age -d -i "$IDENTITY" -o "$MASTER_KEY_DECRYPTED" "$MASTER_KEY_ENC" 2>/dev/null; then
            MASTER_DECRYPTED=true
            USING_MASTER_KEY=true
            echo "   ✓ Decrypted master key using $IDENTITY"
            break
          fi
        done

        if [[ "$MASTER_DECRYPTED" != "true" ]]; then
          echo "   ⚠️ Could not decrypt master key, falling back to direct decryption"
          rm -f "$MASTER_KEY_DECRYPTED"
          MASTER_KEY_DECRYPTED=""
        fi
      fi

      # Set AGE_IDENTITY to first available if not set
      if [[ -z "$AGE_IDENTITY" ]] && [[ ''${#USER_IDENTITIES[@]} -gt 0 ]]; then
        AGE_IDENTITY="''${USER_IDENTITIES[0]}"
      fi

      # Read apps.nix as JSON
      APPS_JSON=$(${pkgs.nix}/bin/nix eval --json --file "$DATA_DIR/apps.nix")

      # Read variables from evaluated flake config (includes computed variables like app ports)
      # This is essential because computed variables don't exist in the data file
      # Try multiple paths: stackpanelConfig.variables first, then data file fallback
      VARS_JSON="{}"
      echo "📖 Reading evaluated variables from flake config..."
      
      # Try evaluating from flake output (includes computed variables)
      if VARS_JSON=$(${pkgs.nix}/bin/nix eval --impure --json '.#stackpanelConfig.variables' 2>/dev/null); then
        echo "   ✓ Using evaluated config (includes computed variables)"
      else
        VARS_JSON="{}"
      fi
      
      # Fall back to data file if flake eval fails (e.g., outside devenv)
      if [[ "$VARS_JSON" == "{}" ]] && [[ -f "$DATA_DIR/variables.nix" ]]; then
        echo "   Using data file fallback (computed variables not available)..."
        VARS_JSON=$(${pkgs.nix}/bin/nix eval --json --file "$DATA_DIR/variables.nix" 2>/dev/null || echo "{}")
      fi

      # Helper function to check if a variable ID refers to an actual SECRET
      is_actual_secret() {
        local var_id="$1"
        if [[ -z "$var_id" ]]; then
          return 1  # No variable ID = not a secret reference
        fi
        # Look up the variable in variables.nix
        local actual_type
        actual_type=$(echo "$VARS_JSON" | ${pkgs.jq}/bin/jq -r --arg id "$var_id" '.[$id].type // "VARIABLE"')
        # Check if actual variable type is SECRET (1 or "SECRET")
        [[ "$actual_type" == "SECRET" ]] || [[ "$actual_type" == "1" ]]
      }

      echo "📦 Generating environment YAML from apps.nix..."

      # Create output directory
      mkdir -p "$OUTPUT_DIR"

      # Process each app
      for APP_NAME in $(echo "$APPS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
        APP_CFG=$(echo "$APPS_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$APP_NAME" '.[$name]')
        ENVS=$(echo "$APP_CFG" | ${pkgs.jq}/bin/jq -r '.environments // {} | keys[]')

        [[ -z "$ENVS" ]] && continue

        # Create app directory in output
        APP_OUTPUT_DIR="$OUTPUT_DIR/$APP_NAME"
        mkdir -p "$APP_OUTPUT_DIR"

        # Process each environment
        for ENV_NAME in $ENVS; do
          ENV_CFG=$(echo "$APP_CFG" | ${pkgs.jq}/bin/jq -r --arg env "$ENV_NAME" '.environments[$env]')
          ENV_VARS=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r '.variables // {} | keys[]')

          [[ -z "$ENV_VARS" ]] && continue

          # Build secrets JSON for this environment
          SECRETS_OBJ="{}"
          HAS_SECRETS=false  # Track if ANY secrets exist in this environment

          for VAR_KEY in $ENV_VARS; do
            VAR_CFG=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r --arg key "$VAR_KEY" '.variables[$key]')
            VAR_ID=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '."variable-id" // empty')
            VAR_ENV_KEY=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '.key // empty')
            VAR_VALUE=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '.value // empty')
            VAR_TYPE=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '.type // 0')

            # Get the env key (fallback to VAR_KEY if not set)
            KEY="''${VAR_ENV_KEY:-$VAR_KEY}"

            # Determine if this is actually a secret:
            # - AppVariableType: 1=LITERAL, 2=VARIABLE (reference), 3=VALS
            # - If type=2 (VARIABLE reference), look up the actual variable's type
            # - VariableType: 0=VARIABLE, 1=SECRET, 2=VALS
            IS_SECRET=false
            if [[ "$VAR_TYPE" == "2" ]] && [[ -n "$VAR_ID" ]]; then
              # Type 2 = VARIABLE reference - check if the referenced variable is a secret
              if is_actual_secret "$VAR_ID"; then
                IS_SECRET=true
                HAS_SECRETS=true  # Mark that this env has at least one secret
              fi
            fi

            if [[ "$IS_SECRET" == "true" ]]; then
              # Look for corresponding .age file in vars/
              # Try different naming conventions
              AGE_FILE=""
              for candidate in "$VAR_ID" "$VAR_KEY" "$KEY"; do
                [[ -z "$candidate" ]] && continue
                # Normalize: replace slashes with dashes, lowercase
                NORMALIZED=$(echo "$candidate" | tr '/' '-' | tr '[:upper:]' '[:lower:]' | sed 's/^-//')
                if [[ -f "$VARS_DIR/$NORMALIZED.age" ]]; then
                  AGE_FILE="$VARS_DIR/$NORMALIZED.age"
                  break
                fi
                if [[ -f "$VARS_DIR/$candidate.age" ]]; then
                  AGE_FILE="$VARS_DIR/$candidate.age"
                  break
                fi
              done

              if [[ -n "$AGE_FILE" ]]; then
                # Decrypt the secret
                DECRYPTED=""
                
                # If using master key (envelope encryption), use the decrypted master key
                if [[ "$USING_MASTER_KEY" == "true" ]] && [[ -n "$MASTER_KEY_DECRYPTED" ]]; then
                  DECRYPTED=$(${pkgs.age}/bin/age -d -i "$MASTER_KEY_DECRYPTED" "$AGE_FILE" 2>/dev/null || echo "")
                fi
                
                # Fall back to trying multiple user identities
                if [[ -z "$DECRYPTED" ]]; then
                  for IDENTITY in "''${USER_IDENTITIES[@]}"; do
                    [[ -z "$IDENTITY" ]] && continue
                    [[ ! -f "$IDENTITY" ]] && continue
                    DECRYPTED=$(${pkgs.age}/bin/age -d -i "$IDENTITY" "$AGE_FILE" 2>/dev/null || echo "")
                    if [[ -n "$DECRYPTED" ]]; then
                      break
                    fi
                  done
                fi
                
                if [[ -n "$DECRYPTED" ]]; then
                  SECRETS_OBJ=$(echo "$SECRETS_OBJ" | ${pkgs.jq}/bin/jq --arg k "$KEY" --arg v "$DECRYPTED" '. + {($k): $v}')
                else
                  echo "⚠️  Could not decrypt $AGE_FILE for $APP_NAME/$ENV_NAME/$KEY"
                fi
              else
                echo "⚠️  No .age file found for secret: $APP_NAME/$ENV_NAME/$KEY (tried: $VAR_ID, $VAR_KEY)"
              fi
            else
              # Regular variable - look up value from referenced variable or use literal value
              RESOLVED_VALUE=""
              if [[ "$VAR_TYPE" == "2" ]] && [[ -n "$VAR_ID" ]]; then
                # Type 2 = VARIABLE reference - look up the value from variables.nix
                RESOLVED_VALUE=$(echo "$VARS_JSON" | ${pkgs.jq}/bin/jq -r --arg id "$VAR_ID" '.[$id].value // empty')
              fi
              # Fall back to literal value if no resolved value
              if [[ -z "$RESOLVED_VALUE" ]] && [[ -n "$VAR_VALUE" ]]; then
                RESOLVED_VALUE="$VAR_VALUE"
              fi
              if [[ -n "$RESOLVED_VALUE" ]]; then
                SECRETS_OBJ=$(echo "$SECRETS_OBJ" | ${pkgs.jq}/bin/jq --arg k "$KEY" --arg v "$RESOLVED_VALUE" '. + {($k): $v}')
              fi
            fi
          done

          # Only create YAML if we have variables
          if [[ "$SECRETS_OBJ" != "{}" ]]; then
            OUTPUT_FILE="$APP_OUTPUT_DIR/$ENV_NAME.yaml"
            
            # Convert JSON to YAML using yq (from json input)
            echo "$SECRETS_OBJ" | ${pkgs.yq-go}/bin/yq -p json -o yaml > "$OUTPUT_FILE.tmp"
            
            # Encrypt with SOPS if there are secrets and .sops.yaml exists
            if [[ -f .sops.yaml ]] && [[ "$HAS_SECRETS" == "true" ]]; then
              # Move to final location first so path matches .sops.yaml regex
              mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
              if ${pkgs.sops}/bin/sops encrypt -i "$OUTPUT_FILE" 2>&1; then
                echo "   ✅ $OUTPUT_FILE (encrypted)"
              else
                echo "   ⚠️  $OUTPUT_FILE (encryption failed, plaintext)"
              fi
            else
              mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
              echo "   ✅ $OUTPUT_FILE"
            fi
          fi
        done
      done

      echo ""
      echo "📦 Environment YAML generation complete!"
      echo "   Output: $OUTPUT_DIR/<app>/<env>.yaml"
    '';

  # Build generate-sops-config script body
  # Generates .sops.yaml from apps.nix environments and their public keys
  generateSopsConfigScript =
    {
      secretsDir,      # .stackpanel/secrets
      dataDir,         # .stackpanel/data
      kmsConfig ? { enable = false; key-arn = ""; aws-profile = ""; },
    }:
    let
      kmsEnabled = kmsConfig.enable or false;
      kmsArn = kmsConfig.key-arn or "";
      kmsProfile = kmsConfig.aws-profile or "";
    in
    ''
      set -e

      DATA_DIR="${dataDir}"
      STATE_DIR=".stackpanel/state"
      KMS_STATE_FILE="$STATE_DIR/kms-config.json"
      OUTPUT_DIR="packages/env/data"  # Where YAML files are written
      # Note: secretsDir (${secretsDir}) is only used for .age files
      
      # Default KMS config from Nix (can be overridden by state file)
      KMS_ENABLED="${if kmsEnabled then "true" else "false"}"
      KMS_ARN="${kmsArn}"
      KMS_PROFILE="${kmsProfile}"
      
      # Check for state file override (takes precedence over Nix config)
      if [[ -f "$KMS_STATE_FILE" ]]; then
        STATE_KMS_ENABLED=$(${pkgs.jq}/bin/jq -r '.enable // false' "$KMS_STATE_FILE")
        STATE_KMS_ARN=$(${pkgs.jq}/bin/jq -r '.keyArn // ""' "$KMS_STATE_FILE")
        STATE_KMS_PROFILE=$(${pkgs.jq}/bin/jq -r '.awsProfile // ""' "$KMS_STATE_FILE")
        
        if [[ "$STATE_KMS_ENABLED" == "true" ]]; then
          KMS_ENABLED="true"
          KMS_ARN="$STATE_KMS_ARN"
          KMS_PROFILE="$STATE_KMS_PROFILE"
          echo "📋 Using KMS config from state file"
        fi
      fi

      # Read apps.nix as JSON
      APPS_JSON=$(${pkgs.nix}/bin/nix eval --json --file "$DATA_DIR/apps.nix")
      
      # Also read external users for fallback keys
      USERS_FILE="$DATA_DIR/external/users.nix"
      if [[ -f "$USERS_FILE" ]]; then
        USERS_JSON=$(${pkgs.nix}/bin/nix eval --json --file "$USERS_FILE")
      else
        USERS_JSON="{}"
      fi

      echo "📦 Generating .sops.yaml from apps.nix..."
      if [[ "$KMS_ENABLED" == "true" ]] && [[ -n "$KMS_ARN" ]]; then
        echo "   AWS KMS enabled: $KMS_ARN"
      fi

      # Start building the SOPS config
      SOPS_CONFIG="# Auto-generated by StackPanel - do not edit manually
# Run 'generate-sops-config' to regenerate

creation_rules:"

      # Collect all public keys from users as fallback
      ALL_USER_KEYS=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -r '
        [.[] | (."public-keys" // .public_keys // .publicKeys // [])[] ] 
        | map(select(startswith("ssh-ed25519") or startswith("age1"))) 
        | unique 
        | .[]' 2>/dev/null || echo "")

      # Process each app
      for APP_NAME in $(echo "$APPS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
        APP_CFG=$(echo "$APPS_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$APP_NAME" '.[$name]')
        ENVS=$(echo "$APP_CFG" | ${pkgs.jq}/bin/jq -r '.environments // {} | keys[]')

        [[ -z "$ENVS" ]] && continue

        # Process each environment
        for ENV_NAME in $ENVS; do
          ENV_CFG=$(echo "$APP_CFG" | ${pkgs.jq}/bin/jq -r --arg env "$ENV_NAME" '.environments[$env]')
          
          # Get public keys for this environment
          PUBLIC_KEYS=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r '."public-keys" // .public_keys // [] | .[]' 2>/dev/null || echo "")
          
          # If no keys defined, use all user keys as fallback
          if [[ -z "$PUBLIC_KEYS" ]]; then
            PUBLIC_KEYS="$ALL_USER_KEYS"
          fi
          
          [[ -z "$PUBLIC_KEYS" ]] && continue

          # Build the rule for this app/env (YAML files are in packages/env/data/)
          SOPS_CONFIG="$SOPS_CONFIG
  - path_regex: ^''${OUTPUT_DIR}/''${APP_NAME}/''${ENV_NAME}\\.yaml$"

          # Add KMS if enabled
          if [[ "$KMS_ENABLED" == "true" ]] && [[ -n "$KMS_ARN" ]]; then
            SOPS_CONFIG="$SOPS_CONFIG
    kms:
      - arn: $KMS_ARN"
            if [[ -n "$KMS_PROFILE" ]]; then
              SOPS_CONFIG="$SOPS_CONFIG
        aws_profile: $KMS_PROFILE"
            fi
          fi

          # Add age keys
          SOPS_CONFIG="$SOPS_CONFIG
    age:"
          
          # Add each public key (convert ssh-ed25519 to age if needed)
          while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            if [[ "$key" == age1* ]]; then
              SOPS_CONFIG="$SOPS_CONFIG
      - $key"
            elif [[ "$key" == ssh-ed25519* ]]; then
              # Convert SSH public key to age recipient using ssh-to-age
              AGE_KEY=$(echo "$key" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
              if [[ -n "$AGE_KEY" ]]; then
                SOPS_CONFIG="$SOPS_CONFIG
      - $AGE_KEY"
              else
                # Can't convert, skip with warning
                echo "⚠️  Could not convert SSH key to age format: $key"
              fi
            fi
          done <<< "$PUBLIC_KEYS"
        done
      done

      # Add a catch-all rule using all user keys
      if [[ -n "$ALL_USER_KEYS" ]]; then
        SOPS_CONFIG="$SOPS_CONFIG
  # Catch-all rule for any other secrets in packages/env/data
  - path_regex: ^''${OUTPUT_DIR}/.*\\.yaml$"

        # Add KMS to catch-all if enabled
        if [[ "$KMS_ENABLED" == "true" ]] && [[ -n "$KMS_ARN" ]]; then
          SOPS_CONFIG="$SOPS_CONFIG
    kms:
      - arn: $KMS_ARN"
          if [[ -n "$KMS_PROFILE" ]]; then
            SOPS_CONFIG="$SOPS_CONFIG
        aws_profile: $KMS_PROFILE"
          fi
        fi

        SOPS_CONFIG="$SOPS_CONFIG
    age:"
        while IFS= read -r key; do
          [[ -z "$key" ]] && continue
          if [[ "$key" == age1* ]]; then
            SOPS_CONFIG="$SOPS_CONFIG
      - $key"
          elif [[ "$key" == ssh-ed25519* ]]; then
            AGE_KEY=$(echo "$key" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
            if [[ -n "$AGE_KEY" ]]; then
              SOPS_CONFIG="$SOPS_CONFIG
      - $AGE_KEY"
            fi
          fi
        done <<< "$ALL_USER_KEYS"
      fi

      # Write the config
      echo "$SOPS_CONFIG" > .sops.yaml
      echo "✅ Generated .sops.yaml"
      echo ""
      echo "Now run 'generate-sops-secrets' to create encrypted YAML files."
    '';

  # ===========================================================================
  # Master Key Management (Envelope Encryption)
  # ===========================================================================
  # Master key architecture:
  #   .stackpanel/secrets/keys/
  #     master.key.age    # Master private key, encrypted for authorized users
  #     master.pub        # Master public key (plaintext, for encrypting secrets)
  #   .stackpanel/secrets/vars/
  #     *.age             # Individual secrets, encrypted with master PUBLIC key
  #
  # Benefits:
  #   - Adding/removing users only re-encrypts the master key
  #   - Secrets stay unchanged when user access changes
  #   - Single point of key rotation
  # ===========================================================================

  # Initialize master key for secrets encryption
  # Creates a new master key pair and encrypts the private key for all users
  # Optionally also encrypts with AWS KMS if configured
  initMasterKeyScript = { kmsEnabled ? false, kmsArn ? "", kmsProfile ? "" }: ''
    set -e

    KEYS_DIR=".stackpanel/secrets/keys"
    MASTER_KEY="$KEYS_DIR/master.key"
    MASTER_PUB="$KEYS_DIR/master.pub"
    MASTER_KEY_ENC="$KEYS_DIR/master.key.age"
    MASTER_KEY_KMS="$KEYS_DIR/master.key.kms"
    USERS_FILE=".stackpanel/secrets/users.nix"
    KMS_ENABLED="${if kmsEnabled then "true" else "false"}"
    KMS_ARN="${kmsArn}"
    KMS_PROFILE="${kmsProfile}"

    # Check if master key already exists
    if [[ -f "$MASTER_KEY_ENC" ]]; then
      echo "⚠️  Master key already exists at $MASTER_KEY_ENC"
      echo "   To rotate, use: secrets:rotate-master"
      exit 0
    fi

    echo "🔐 Initializing master key for envelope encryption..."
    ${lib.optionalString kmsEnabled ''
    echo "   KMS: $KMS_ARN"
    ''}

    # Create keys directory
    mkdir -p "$KEYS_DIR"
    chmod 700 "$KEYS_DIR"

    # Generate new master key pair
    echo "📝 Generating new master key pair..."
    ${pkgs.age}/bin/age-keygen -o "$MASTER_KEY" 2>/dev/null
    chmod 600 "$MASTER_KEY"

    # Extract public key
    PUBLIC_KEY=$(${pkgs.age}/bin/age-keygen -y "$MASTER_KEY")
    echo "$PUBLIC_KEY" > "$MASTER_PUB"
    echo "   Public key: $PUBLIC_KEY"

    # Collect user public keys
    echo "📋 Collecting user public keys..."
    RECIPIENTS=()

    # From users.nix if it exists
    if [[ -f "$USERS_FILE" ]]; then
      USER_KEYS=$(${pkgs.nix}/bin/nix eval --json --file "$USERS_FILE" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[].["public-key"] // empty' 2>/dev/null || echo "")
      while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        if [[ "$key" == age1* ]]; then
          RECIPIENTS+=("-r" "$key")
          echo "   + $key (from users.nix)"
        elif [[ "$key" == ssh-* ]]; then
          AGE_KEY=$(echo "$key" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
          if [[ -n "$AGE_KEY" ]]; then
            RECIPIENTS+=("-r" "$AGE_KEY")
            echo "   + $AGE_KEY (converted from SSH)"
          fi
        fi
      done <<< "$USER_KEYS"
    fi

    # Also add the local state key if it exists
    STATE_KEY=".stackpanel/state/age-key.txt"
    if [[ -f "$STATE_KEY" ]]; then
      LOCAL_PUB=$(${pkgs.age}/bin/age-keygen -y "$STATE_KEY" 2>/dev/null)
      if [[ -n "$LOCAL_PUB" ]]; then
        RECIPIENTS+=("-r" "$LOCAL_PUB")
        echo "   + $LOCAL_PUB (local state key)"
      fi
    fi

    # Add current user's SSH key if available
    for SSH_KEY in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
      if [[ -f "$SSH_KEY" ]]; then
        SSH_PUB=$(cat "$SSH_KEY")
        AGE_KEY=$(echo "$SSH_PUB" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
        if [[ -n "$AGE_KEY" ]]; then
          RECIPIENTS+=("-r" "$AGE_KEY")
          echo "   + $AGE_KEY (from $SSH_KEY)"
          break
        fi
      fi
    done

    if [[ ''${#RECIPIENTS[@]} -eq 0 ]]; then
      echo "❌ Error: No recipient keys found!"
      echo "   Add users to .stackpanel/secrets/users.nix or ensure you have an SSH key."
      rm -f "$MASTER_KEY" "$MASTER_PUB"
      exit 1
    fi

    # Encrypt master key for all AGE recipients
    echo "🔒 Encrypting master key for ''${#RECIPIENTS[@]} AGE recipients..."
    ${pkgs.age}/bin/age "''${RECIPIENTS[@]}" -o "$MASTER_KEY_ENC" "$MASTER_KEY"

    # Also encrypt with KMS if enabled
    if [[ "$KMS_ENABLED" == "true" ]] && [[ -n "$KMS_ARN" ]]; then
      echo "☁️  Also encrypting with AWS KMS..."
      AWS_ARGS=()
      if [[ -n "$KMS_PROFILE" ]]; then
        AWS_ARGS+=("--profile" "$KMS_PROFILE")
      fi
      
      # Create a KMS-encrypted copy of the master key
      if ${pkgs.awscli2}/bin/aws kms encrypt \
          "''${AWS_ARGS[@]}" \
          --key-id "$KMS_ARN" \
          --plaintext "fileb://$MASTER_KEY" \
          --output text \
          --query CiphertextBlob > "$MASTER_KEY_KMS" 2>/dev/null; then
        echo "   ✓ KMS-encrypted copy: $MASTER_KEY_KMS"
      else
        echo "   ⚠️ KMS encryption failed (AWS credentials may not be configured)"
        echo "   The AGE-encrypted key will still work for local development"
        rm -f "$MASTER_KEY_KMS"
      fi
    fi

    # Remove plaintext master key (keep only encrypted version)
    rm -f "$MASTER_KEY"

    echo ""
    echo "✅ Master key initialized!"
    echo "   AGE-encrypted: $MASTER_KEY_ENC"
    echo "   Public key:    $MASTER_PUB"
    if [[ -f "$MASTER_KEY_KMS" ]]; then
      echo "   KMS-encrypted: $MASTER_KEY_KMS"
    fi
    echo ""
    echo "📝 Next steps:"
    echo "   1. Commit $MASTER_KEY_ENC and $MASTER_PUB to git"
    echo "   2. New secrets will be encrypted with the master key"
    echo "   3. To migrate existing secrets: secrets:migrate-to-master"
  '';

  # Add a user to the master key recipients
  addUserToMasterKeyScript = ''
    set -e

    KEYS_DIR=".stackpanel/secrets/keys"
    MASTER_KEY_ENC="$KEYS_DIR/master.key.age"
    USERS_FILE=".stackpanel/secrets/users.nix"

    if [[ ! -f "$MASTER_KEY_ENC" ]]; then
      echo "❌ Error: Master key not found. Run 'secrets:init-master' first."
      exit 1
    fi

    NEW_USER="$1"
    if [[ -z "$NEW_USER" ]]; then
      echo "Usage: secrets:add-user <username or public-key>"
      echo ""
      echo "Examples:"
      echo "  secrets:add-user alice                    # Add user 'alice' from users.nix"
      echo "  secrets:add-user age1abc123...            # Add by AGE public key"
      echo "  secrets:add-user 'ssh-ed25519 AAAA...'    # Add by SSH public key"
      exit 1
    fi

    echo "🔐 Adding user to master key recipients..."

    # Find all identity files that can decrypt the master key
    IDENTITY=""
    for loc in .stackpanel/state/age-key.txt ~/.config/sops/age/keys.txt ~/.ssh/id_ed25519; do
      if [[ -f "$loc" ]]; then
        if ${pkgs.age}/bin/age -d -i "$loc" "$MASTER_KEY_ENC" >/dev/null 2>&1; then
          IDENTITY="$loc"
          break
        fi
      fi
    done

    if [[ -z "$IDENTITY" ]]; then
      echo "❌ Error: Cannot decrypt master key with any available identity."
      exit 1
    fi

    # Decrypt master key to temp file
    TEMP_KEY=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$TEMP_KEY'" EXIT
    ${pkgs.age}/bin/age -d -i "$IDENTITY" -o "$TEMP_KEY" "$MASTER_KEY_ENC"

    # Collect all existing recipients
    RECIPIENTS=()

    # From users.nix
    if [[ -f "$USERS_FILE" ]]; then
      USER_KEYS=$(${pkgs.nix}/bin/nix eval --json --file "$USERS_FILE" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[].["public-key"] // empty' 2>/dev/null || echo "")
      while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        if [[ "$key" == age1* ]]; then
          RECIPIENTS+=("-r" "$key")
        elif [[ "$key" == ssh-* ]]; then
          AGE_KEY=$(echo "$key" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
          [[ -n "$AGE_KEY" ]] && RECIPIENTS+=("-r" "$AGE_KEY")
        fi
      done <<< "$USER_KEYS"
    fi

    # Add local state key
    STATE_KEY=".stackpanel/state/age-key.txt"
    if [[ -f "$STATE_KEY" ]]; then
      LOCAL_PUB=$(${pkgs.age}/bin/age-keygen -y "$STATE_KEY" 2>/dev/null)
      [[ -n "$LOCAL_PUB" ]] && RECIPIENTS+=("-r" "$LOCAL_PUB")
    fi

    # Add the new user
    NEW_KEY=""
    if [[ "$NEW_USER" == age1* ]]; then
      NEW_KEY="$NEW_USER"
    elif [[ "$NEW_USER" == ssh-* ]]; then
      NEW_KEY=$(echo "$NEW_USER" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
    else
      # Look up in users.nix
      NEW_KEY=$(${pkgs.nix}/bin/nix eval --json --file "$USERS_FILE" 2>/dev/null | \
        ${pkgs.jq}/bin/jq -r --arg name "$NEW_USER" '.[$name]["public-key"] // empty' 2>/dev/null || echo "")
      if [[ "$NEW_KEY" == ssh-* ]]; then
        NEW_KEY=$(echo "$NEW_KEY" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
      fi
    fi

    if [[ -z "$NEW_KEY" ]] || [[ "$NEW_KEY" != age1* ]]; then
      echo "❌ Error: Could not resolve public key for '$NEW_USER'"
      exit 1
    fi

    RECIPIENTS+=("-r" "$NEW_KEY")
    echo "   Adding: $NEW_KEY"

    # Re-encrypt master key with all recipients
    ${pkgs.age}/bin/age "''${RECIPIENTS[@]}" -o "$MASTER_KEY_ENC.new" "$TEMP_KEY"
    mv "$MASTER_KEY_ENC.new" "$MASTER_KEY_ENC"

    echo "✅ User added to master key recipients!"
    echo "   Commit $MASTER_KEY_ENC to share access."
  '';

  # Remove a user from master key recipients
  removeUserFromMasterKeyScript = ''
    set -e

    KEYS_DIR=".stackpanel/secrets/keys"
    MASTER_KEY_ENC="$KEYS_DIR/master.key.age"
    USERS_FILE=".stackpanel/secrets/users.nix"

    if [[ ! -f "$MASTER_KEY_ENC" ]]; then
      echo "❌ Error: Master key not found."
      exit 1
    fi

    REMOVE_USER="$1"
    if [[ -z "$REMOVE_USER" ]]; then
      echo "Usage: secrets:remove-user <username or public-key>"
      exit 1
    fi

    echo "🔐 Removing user from master key recipients..."

    # Find identity that can decrypt
    IDENTITY=""
    for loc in .stackpanel/state/age-key.txt ~/.config/sops/age/keys.txt ~/.ssh/id_ed25519; do
      if [[ -f "$loc" ]]; then
        if ${pkgs.age}/bin/age -d -i "$loc" "$MASTER_KEY_ENC" >/dev/null 2>&1; then
          IDENTITY="$loc"
          break
        fi
      fi
    done

    if [[ -z "$IDENTITY" ]]; then
      echo "❌ Error: Cannot decrypt master key."
      exit 1
    fi

    # Decrypt master key
    TEMP_KEY=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$TEMP_KEY'" EXIT
    ${pkgs.age}/bin/age -d -i "$IDENTITY" -o "$TEMP_KEY" "$MASTER_KEY_ENC"

    # Resolve the key to remove
    REMOVE_KEY=""
    if [[ "$REMOVE_USER" == age1* ]]; then
      REMOVE_KEY="$REMOVE_USER"
    elif [[ "$REMOVE_USER" == ssh-* ]]; then
      REMOVE_KEY=$(echo "$REMOVE_USER" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
    else
      REMOVE_KEY=$(${pkgs.nix}/bin/nix eval --json --file "$USERS_FILE" 2>/dev/null | \
        ${pkgs.jq}/bin/jq -r --arg name "$REMOVE_USER" '.[$name]["public-key"] // empty' 2>/dev/null || echo "")
      if [[ "$REMOVE_KEY" == ssh-* ]]; then
        REMOVE_KEY=$(echo "$REMOVE_KEY" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
      fi
    fi

    echo "   Removing: $REMOVE_KEY"

    # Collect all recipients EXCEPT the one to remove
    RECIPIENTS=()

    if [[ -f "$USERS_FILE" ]]; then
      USER_KEYS=$(${pkgs.nix}/bin/nix eval --json --file "$USERS_FILE" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[].["public-key"] // empty' 2>/dev/null || echo "")
      while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        AGE_KEY="$key"
        if [[ "$key" == ssh-* ]]; then
          AGE_KEY=$(echo "$key" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || echo "")
        fi
        # Skip if this is the key to remove
        if [[ "$AGE_KEY" != "$REMOVE_KEY" ]] && [[ "$AGE_KEY" == age1* ]]; then
          RECIPIENTS+=("-r" "$AGE_KEY")
        fi
      done <<< "$USER_KEYS"
    fi

    # Add local state key (unless it's being removed)
    STATE_KEY=".stackpanel/state/age-key.txt"
    if [[ -f "$STATE_KEY" ]]; then
      LOCAL_PUB=$(${pkgs.age}/bin/age-keygen -y "$STATE_KEY" 2>/dev/null)
      if [[ -n "$LOCAL_PUB" ]] && [[ "$LOCAL_PUB" != "$REMOVE_KEY" ]]; then
        RECIPIENTS+=("-r" "$LOCAL_PUB")
      fi
    fi

    if [[ ''${#RECIPIENTS[@]} -eq 0 ]]; then
      echo "❌ Error: Cannot remove last recipient!"
      exit 1
    fi

    # Re-encrypt without removed user
    ${pkgs.age}/bin/age "''${RECIPIENTS[@]}" -o "$MASTER_KEY_ENC.new" "$TEMP_KEY"
    mv "$MASTER_KEY_ENC.new" "$MASTER_KEY_ENC"

    echo "✅ User removed from master key recipients!"
    echo ""
    echo "⚠️  If user had access to decrypted secrets, consider rotating:"
    echo "   secrets:rotate-master"
  '';

  # Migrate existing .age files to use master key encryption
  migrateToMasterKeyScript = ''
    set -e

    KEYS_DIR=".stackpanel/secrets/keys"
    MASTER_KEY_ENC="$KEYS_DIR/master.key.age"
    MASTER_PUB="$KEYS_DIR/master.pub"
    VARS_DIR=".stackpanel/secrets/vars"

    if [[ ! -f "$MASTER_KEY_ENC" ]]; then
      echo "❌ Error: Master key not found. Run 'secrets:init-master' first."
      exit 1
    fi

    if [[ ! -f "$MASTER_PUB" ]]; then
      echo "❌ Error: Master public key not found at $MASTER_PUB"
      exit 1
    fi

    MASTER_PUBLIC=$(cat "$MASTER_PUB")
    echo "🔄 Migrating secrets to master key encryption..."
    echo "   Master public key: $MASTER_PUBLIC"

    # Find identity to decrypt existing secrets
    IDENTITY=""
    for loc in .stackpanel/state/age-key.txt ~/.config/sops/age/keys.txt ~/.ssh/id_ed25519 ~/.ssh/id_rsa; do
      [[ -f "$loc" ]] && IDENTITY="$loc" && break
    done

    if [[ -z "$IDENTITY" ]]; then
      echo "❌ Error: No identity found to decrypt existing secrets."
      exit 1
    fi

    MIGRATED=0
    FAILED=0

    for AGE_FILE in "$VARS_DIR"/*.age; do
      [[ ! -f "$AGE_FILE" ]] && continue
      
      BASENAME=$(basename "$AGE_FILE")
      echo -n "   $BASENAME: "

      # Try to decrypt
      TEMP_VALUE=$(mktemp)
      if ${pkgs.age}/bin/age -d -i "$IDENTITY" "$AGE_FILE" > "$TEMP_VALUE" 2>/dev/null; then
        # Re-encrypt with master key
        ${pkgs.age}/bin/age -r "$MASTER_PUBLIC" -o "$AGE_FILE.new" "$TEMP_VALUE"
        mv "$AGE_FILE.new" "$AGE_FILE"
        echo "✅ migrated"
        MIGRATED=$((MIGRATED + 1))
      else
        echo "⚠️ skipped (cannot decrypt)"
        FAILED=$((FAILED + 1))
      fi
      rm -f "$TEMP_VALUE"
    done

    echo ""
    echo "✅ Migration complete!"
    echo "   Migrated: $MIGRATED secrets"
    [[ $FAILED -gt 0 ]] && echo "   Skipped:  $FAILED secrets (could not decrypt)"
    echo ""
    echo "📝 Commit the updated .age files to git."
  '';

  # Decrypt the master key and return the path to the decrypted key file
  # This is a helper function used by other scripts
  decryptMasterKeyScript = ''
    decrypt_master_key() {
      local MASTER_KEY_ENC=".stackpanel/secrets/keys/master.key.age"
      local TEMP_KEY
      
      if [[ ! -f "$MASTER_KEY_ENC" ]]; then
        return 1
      fi

      TEMP_KEY=$(mktemp)
      
      # Try each identity
      for loc in .stackpanel/state/age-key.txt ~/.config/sops/age/keys.txt ~/.ssh/id_ed25519 ~/.ssh/id_rsa; do
        [[ ! -f "$loc" ]] && continue
        if ${pkgs.age}/bin/age -d -i "$loc" -o "$TEMP_KEY" "$MASTER_KEY_ENC" 2>/dev/null; then
          echo "$TEMP_KEY"
          return 0
        fi
      done

      rm -f "$TEMP_KEY"
      return 1
    }
  '';
}
