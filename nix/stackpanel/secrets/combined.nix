# ==============================================================================
# combined.nix
#
# Module for generating combined encrypted secrets per app environment.
# This module takes individual secrets and combines them into encrypted YAML
# files that can be used by applications at runtime.
#
# Structure:
#   .stackpanel/secrets/
#   ├── vars/                  # Individual secret .age files
#   │   ├── database-url.age
#   │   └── api-key.age
#   └── apps/
#       └── myapp/
#           ├── config.nix     # App configuration
#           ├── common.nix     # Shared schema across environments
#           ├── dev.nix        # Dev environment config
#           ├── dev.yaml       # Combined encrypted secrets for dev
#           ├── staging.yaml   # Combined encrypted secrets for staging
#           └── prod.yaml      # Combined encrypted secrets for prod
#
# Usage:
#   The generated YAML files contain all secrets relevant to that app/environment,
#   encrypted with the appropriate public keys. At runtime, applications use
#   SOPS or vals to decrypt and access these secrets.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.secrets;

  # Convert age key files list to bash array string
  ageKeyLocationsArray = lib.concatMapStringsSep "\n      " (loc: ''"${loc}"'') cfg.age-key-files;

  # Standard environments
  standardEnvs = [
    "dev"
    "staging"
    "prod"
  ];

  # Generate the script to combine secrets for an app environment
  generateCombineScript = pkgs.writeShellApplication {
    name = "combine-app-secrets";
    runtimeInputs = [
      pkgs.age
      pkgs.yq-go
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      usage() {
        echo "Usage: combine-app-secrets <project-root> <app-name> <environment>"
        echo ""
        echo "Combines individual .age secrets into a single encrypted YAML for an app environment."
        echo ""
        echo "Arguments:"
        echo "  project-root  Path to the project root directory"
        echo "  app-name      Name of the application"
        echo "  environment   Target environment (dev, staging, prod)"
        exit 1
      }

      [[ $# -lt 3 ]] && usage

      PROJECT_ROOT="$1"
      APP_NAME="$2"
      ENV_NAME="$3"

      SECRETS_DIR="$PROJECT_ROOT/.stackpanel/secrets"
      VARS_DIR="$SECRETS_DIR/vars"
      APP_DIR="$SECRETS_DIR/apps/$APP_NAME"
      OUTPUT_FILE="$APP_DIR/$ENV_NAME.yaml"

      # Check configured locations for AGE key file
      AGE_KEY_LOCATIONS=(
        ${ageKeyLocationsArray}
      )

      AGE_KEY_FILE=""
      for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
        [[ -z "$loc" ]] && continue
        if [[ -f "$loc" ]]; then
          AGE_KEY_FILE="$loc"
          break
        fi
      done

      if [[ -z "$AGE_KEY_FILE" ]]; then
        echo "Error: AGE key file not found in any of these locations:" >&2
        for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
          [[ -n "$loc" ]] && echo "  - $loc" >&2
        done
        echo "Set SOPS_AGE_KEY_FILE or create the key file." >&2
        exit 1
      fi

      if [[ ! -d "$VARS_DIR" ]]; then
        echo "Error: Secrets directory not found: $VARS_DIR" >&2
        exit 1
      fi

      if [[ ! -d "$APP_DIR" ]]; then
        echo "Error: App directory not found: $APP_DIR" >&2
        exit 1
      fi

      # Get recipients from the app's environment config
      ENV_CONFIG="$APP_DIR/$ENV_NAME.nix"

      # Function to get public keys from nix config
      get_recipients() {
        local config_file="$1"
        if [[ -f "$config_file" ]]; then
          # Try to extract extraKeys and user pubkeys via nix eval
          nix eval --impure --json -f "$config_file" 2>/dev/null | jq -r '.extraKeys // [] | .[]' 2>/dev/null || true
        fi
      }

      # Collect recipients
      RECIPIENTS=()

      # Add extraKeys from env config
      while IFS= read -r key; do
        [[ -n "$key" ]] && RECIPIENTS+=("$key")
      done < <(get_recipients "$ENV_CONFIG")

      # If no recipients found, try to get from users.nix via the project's nix config
      if [[ ''${#RECIPIENTS[@]} -eq 0 ]]; then
        echo "Warning: No recipients found in $ENV_CONFIG, using all available keys" >&2
        # Fall back to reading from the evaluated config
        while IFS= read -r key; do
          [[ -n "$key" && "$key" == age1* ]] && RECIPIENTS+=("$key")
        done < <(nix eval --impure --json "$PROJECT_ROOT#stackpanelFullConfig.secrets.agenix-config" 2>/dev/null | jq -r '.[].publicKeys[]' 2>/dev/null || true)
      fi

      if [[ ''${#RECIPIENTS[@]} -eq 0 ]]; then
        echo "Error: No recipients found for encryption" >&2
        exit 1
      fi

      echo "Combining secrets for $APP_NAME ($ENV_NAME)..."
      echo "Recipients: ''${#RECIPIENTS[@]} keys"

      # Create temp file for combined plaintext
      TEMP_YAML=$(mktemp)
      trap 'rm -f "$TEMP_YAML"' EXIT

      # Start YAML document
      {
        echo "# Combined secrets for $APP_NAME ($ENV_NAME)"
        echo "# Generated at: $(date -Iseconds)"
        echo "# DO NOT EDIT - regenerate with: combine-app-secrets"
        echo ""
      } > "$TEMP_YAML"

      # Decrypt and combine each .age file
      SECRET_COUNT=0
      for age_file in "$VARS_DIR"/*.age; do
        [[ -f "$age_file" ]] || continue

        secret_name=$(basename "$age_file" .age)
        echo "  Adding: $secret_name"

        # Decrypt the secret
        secret_value=$(age -d -i "$AGE_KEY_FILE" "$age_file" 2>/dev/null) || {
          echo "Warning: Failed to decrypt $age_file, skipping" >&2
          continue
        }

        # Add to YAML (properly escaped)
        {
          echo "$secret_name: |"
          echo "$secret_value" | while IFS= read -r line; do echo "  $line"; done
        } >> "$TEMP_YAML"

        ((SECRET_COUNT++))
      done

      if [[ $SECRET_COUNT -eq 0 ]]; then
        echo "Warning: No secrets were combined" >&2
      fi

      # Build age encryption command
      AGE_ARGS=(-e)
      for r in "''${RECIPIENTS[@]}"; do
        AGE_ARGS+=(-r "$r")
      done
      AGE_ARGS+=(-o "$OUTPUT_FILE")

      # Encrypt the combined YAML
      mkdir -p "$(dirname "$OUTPUT_FILE")"
      age "''${AGE_ARGS[@]}" "$TEMP_YAML"

      echo "Done! Combined $SECRET_COUNT secrets into $OUTPUT_FILE"
    '';
  };

  # Generate the script to decrypt and output combined secrets
  generateDecryptScript = pkgs.writeShellApplication {
    name = "decrypt-app-secrets";
    runtimeInputs = [
      pkgs.age
      pkgs.yq-go
    ];
    text = ''
      set -euo pipefail

      usage() {
        echo "Usage: decrypt-app-secrets <combined-yaml> [format]"
        echo ""
        echo "Decrypts a combined secrets YAML and outputs in the specified format."
        echo ""
        echo "Arguments:"
        echo "  combined-yaml  Path to the encrypted combined YAML file"
        echo "  format         Output format: yaml (default), json, env, dotenv"
        exit 1
      }

      [[ $# -lt 1 ]] && usage

      INPUT_FILE="$1"
      FORMAT="''${2:-yaml}"

      # Check configured locations for AGE key file
      AGE_KEY_LOCATIONS=(
        ${ageKeyLocationsArray}
      )

      AGE_KEY_FILE=""
      for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
        [[ -z "$loc" ]] && continue
        if [[ -f "$loc" ]]; then
          AGE_KEY_FILE="$loc"
          break
        fi
      done

      if [[ -z "$AGE_KEY_FILE" ]]; then
        echo "Error: AGE key file not found in any of these locations:" >&2
        for loc in "''${AGE_KEY_LOCATIONS[@]}"; do
          [[ -n "$loc" ]] && echo "  - $loc" >&2
        done
        exit 1
      fi

      if [[ ! -f "$INPUT_FILE" ]]; then
        echo "Error: Input file not found: $INPUT_FILE" >&2
        exit 1
      fi

      # Try to decrypt with AGE key first
      DECRYPTED=$(age -d -i "$AGE_KEY_FILE" "$INPUT_FILE" 2>/dev/null) || {
        # If AGE key fails, try SSH keys
        echo "AGE key decryption failed, trying SSH keys..." >&2
        
        # Try common SSH key locations
        SSH_KEYS=(
          "$HOME/.ssh/id_ed25519"
          "$HOME/.ssh/id_rsa"
        )
        
        DECRYPTED=""
        for ssh_key in "''${SSH_KEYS[@]}"; do
          if [[ -f "$ssh_key" ]]; then
            echo "  Trying $ssh_key..." >&2
            if DECRYPTED=$(age -d -i "$ssh_key" "$INPUT_FILE" 2>/dev/null); then
              echo "  ✓ Successfully decrypted with $ssh_key" >&2
              break
            fi
          fi
        done
        
        if [[ -z "$DECRYPTED" ]]; then
          echo "Error: Could not decrypt file with AGE key or any SSH keys" >&2
          echo "Tried:" >&2
          echo "  - AGE key: $AGE_KEY_FILE" >&2
          for ssh_key in "''${SSH_KEYS[@]}"; do
            [[ -f "$ssh_key" ]] && echo "  - SSH key: $ssh_key" >&2
          done
          exit 1
        fi
      }

      case "$FORMAT" in
        yaml)
          echo "$DECRYPTED"
          ;;
        json)
          echo "$DECRYPTED" | yq -o json
          ;;
        env|dotenv)
          # Convert to KEY=value format
          echo "$DECRYPTED" | yq -o json | jq -r 'to_entries | .[] | "\(.key)=\(.value)"'
          ;;
        *)
          echo "Error: Unknown format: $FORMAT" >&2
          echo "Supported formats: yaml, json, env, dotenv" >&2
          exit 1
          ;;
      esac
    '';
  };

  # Generate the script to regenerate all combined secrets
  generateRegenerateAllScript = pkgs.writeShellApplication {
    name = "regenerate-all-secrets";
    runtimeInputs = [
      pkgs.age
      pkgs.yq-go
      pkgs.jq
      pkgs.coreutils
      generateCombineScript
    ];
    text = ''
      set -euo pipefail

      PROJECT_ROOT="''${1:-.}"
      APPS_DIR="$PROJECT_ROOT/.stackpanel/secrets/apps"

      if [[ ! -d "$APPS_DIR" ]]; then
        echo "No apps directory found at $APPS_DIR"
        exit 0
      fi

      echo "Regenerating combined secrets for all apps..."
      echo ""

      for app_dir in "$APPS_DIR"/*/; do
        [[ -d "$app_dir" ]] || continue

        app_name=$(basename "$app_dir")

        # Skip example directories
        [[ "$app_name" == _* ]] && continue

        echo "=== App: $app_name ==="

        for env in dev staging prod; do
          env_config="$app_dir/$env.nix"
          if [[ -f "$env_config" ]]; then
            echo "  Generating $env..."
            combine-app-secrets "$PROJECT_ROOT" "$app_name" "$env" || {
              echo "  Warning: Failed to generate $env for $app_name" >&2
            }
          fi
        done

        echo ""
      done

      echo "Done!"
    '';
  };

in
{
  options.stackpanel.secrets.combined = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable generation of combined encrypted secrets per app environment.
        When enabled, the module provides scripts to combine individual .age
        files into single encrypted YAML files for each app environment.
      '';
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the application";
            };

            environments = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = standardEnvs;
              description = "List of environments to generate combined secrets for";
            };

            variables = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                List of variable IDs to include in the combined secrets.
                If empty, all secrets available for the environment are included.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Per-app configuration for combined secrets generation.
        Allows fine-grained control over which secrets are included for each app.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.combined.enable) {
    # Add packages to devshell
    stackpanel.devshell.packages = [
      generateCombineScript
      generateDecryptScript
      generateRegenerateAllScript
    ];

    # Add scripts
    stackpanel.scripts = {
      "secrets:combine" = {
        description = "Combine secrets for an app environment (args: <app-name> <environment>)";
        exec = ''
          combine-app-secrets "$(pwd)" "$@"
        '';
      };

      "secrets:decrypt" = {
        description = "Decrypt and output combined secrets (args: <file> [format])";
        exec = "decrypt-app-secrets";
      };

      "secrets:regenerate-all" = {
        description = "Regenerate combined secrets for all apps";
        exec = ''
          regenerate-all-secrets "$(pwd)"
        '';
      };
    };

    # Expose configuration for the agent
    stackpanel.serializable.secrets.combined = {
      enable = cfg.combined.enable;
      apps = cfg.combined.apps;
      standardEnvironments = standardEnvs;
    };
  };
}
