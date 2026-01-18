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

    if [[ -z "$KEYFILE" ]]; then
      echo "❌ Error: AGE key file not found in any of these locations:" >&2
      for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
        [[ -n "$loc" ]] && echo "  - $loc" >&2
      done
      echo "" >&2
      echo "Follow the instructions to add the decryption key:" >&2
      echo "1. Find 'SOPS (Dev)' in 1Password > Dev Vault" >&2
      echo "2. Copy the AGE secret key (password)" >&2
      echo "3. Add it to ~/.config/sops/age/keys.txt (or set SOPS_AGE_KEY_FILE)" >&2
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

  # Build generate-sops-secrets script body
  # Generates SOPS YAML files from agenix secrets (.age files) and apps.nix
  # Takes cfg values as arguments to bake in at build time
  generateSopsSecretsScript =
    {
      secretsDir,      # .stackpanel/secrets
      dataDir,         # .stackpanel/data
      ageIdentityFile, # Path to AGE/SSH private key for decryption
    }:
    ''
      set -e

      SECRETS_DIR="${secretsDir}"
      DATA_DIR="${dataDir}"
      VARS_DIR="$SECRETS_DIR/vars"
      AGE_IDENTITY="${ageIdentityFile}"

      # Check if age identity exists
      if [[ -n "$AGE_IDENTITY" && ! -f "$AGE_IDENTITY" ]]; then
        echo "❌ Error: AGE identity file not found: $AGE_IDENTITY" >&2
        echo "Set a valid path or leave empty for default locations." >&2
        exit 1
      fi

      # Find AGE identity if not specified
      if [[ -z "$AGE_IDENTITY" ]]; then
        for loc in ~/.config/age/key.txt ~/.age/key.txt ~/.config/sops/age/keys.txt; do
          if [[ -f "$loc" ]]; then
            AGE_IDENTITY="$loc"
            break
          fi
        done
      fi

      # Read apps.nix as JSON
      APPS_JSON=$(${pkgs.nix}/bin/nix eval --json --file "$DATA_DIR/apps.nix")

      echo "📦 Generating SOPS secrets from apps.nix..."

      # Process each app
      for APP_NAME in $(echo "$APPS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
        APP_CFG=$(echo "$APPS_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$APP_NAME" '.[$name]')
        ENVS=$(echo "$APP_CFG" | ${pkgs.jq}/bin/jq -r '.environments // {} | keys[]')

        [[ -z "$ENVS" ]] && continue

        # Create app directory
        APP_DIR="$SECRETS_DIR/$APP_NAME"
        mkdir -p "$APP_DIR"

        # Process each environment
        for ENV_NAME in $ENVS; do
          ENV_CFG=$(echo "$APP_CFG" | ${pkgs.jq}/bin/jq -r --arg env "$ENV_NAME" '.environments[$env]')
          ENV_VARS=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r '.variables // {} | keys[]')

          [[ -z "$ENV_VARS" ]] && continue

          # Build secrets JSON for this environment
          SECRETS_OBJ="{}"

          for VAR_KEY in $ENV_VARS; do
            VAR_CFG=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r --arg key "$VAR_KEY" '.variables[$key]')
            VAR_ID=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '."variable-id" // empty')
            VAR_ENV_KEY=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '.key // empty')
            VAR_VALUE=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '.value // empty')
            VAR_TYPE=$(echo "$VAR_CFG" | ${pkgs.jq}/bin/jq -r '.type // 0')

            # Get the env key (fallback to VAR_KEY if not set)
            KEY="''${VAR_ENV_KEY:-$VAR_KEY}"

            # Check if this is a SECRET (type = "SECRET" or type = 2)
            if [[ "$VAR_TYPE" == "SECRET" ]] || [[ "$VAR_TYPE" == "2" ]]; then
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
                if [[ -n "$AGE_IDENTITY" ]]; then
                  DECRYPTED=$(${pkgs.age}/bin/age -d -i "$AGE_IDENTITY" "$AGE_FILE" 2>/dev/null || echo "")
                else
                  DECRYPTED=$(${pkgs.age}/bin/age -d "$AGE_FILE" 2>/dev/null || echo "")
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
              # Regular variable - use value directly if present
              if [[ -n "$VAR_VALUE" ]]; then
                SECRETS_OBJ=$(echo "$SECRETS_OBJ" | ${pkgs.jq}/bin/jq --arg k "$KEY" --arg v "$VAR_VALUE" '. + {($k): $v}')
              fi
            fi
          done

          # Only create YAML if we have secrets
          if [[ "$SECRETS_OBJ" != "{}" ]]; then
            OUTPUT_FILE="$APP_DIR/$ENV_NAME.yaml"
            
            # Convert JSON to YAML using yq (from json input)
            echo "$SECRETS_OBJ" | ${pkgs.yq-go}/bin/yq -p json -o yaml > "$OUTPUT_FILE.tmp"
            
            # Check if SOPS config exists
            if [[ -f .sops.yaml ]]; then
              # Move to final location first so path matches .sops.yaml regex
              mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
              if ${pkgs.sops}/bin/sops encrypt -i "$OUTPUT_FILE" 2>&1; then
                echo "✅ Generated $OUTPUT_FILE (encrypted)"
              else
                echo "⚠️  Failed to encrypt $OUTPUT_FILE - saved as plaintext"
              fi
            else
              mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
              echo "⚠️  No .sops.yaml found, creating unencrypted YAML (run 'generate-sops-config' first)"
            fi
          fi
        done
      done

      echo ""
      echo "🔐 SOPS secrets generation complete!"
      echo "   Output: $SECRETS_DIR/<app>/<env>.yaml"
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

      SECRETS_DIR="${secretsDir}"
      DATA_DIR="${dataDir}"
      STATE_DIR=".stackpanel/state"
      KMS_STATE_FILE="$STATE_DIR/kms-config.json"
      
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

          # Build the rule for this app/env
          SOPS_CONFIG="$SOPS_CONFIG
  - path_regex: ^''${SECRETS_DIR}/''${APP_NAME}/''${ENV_NAME}\\.yaml$"

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
  # Catch-all rule for any other secrets
  - path_regex: ^''${SECRETS_DIR}/.*\\.yaml$"

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
}
