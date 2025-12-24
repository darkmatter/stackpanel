# Builds typed secrets packages
{pkgs, lib, config, ... }: let
  cfg = config.stackpanel.secrets;
in  {
  options.stackpanel.secrets = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable StackPanel secrets utilities.";
    };
    input-directory = lib.mkOption {
      type = lib.types.str;
      description = "Directory where your secrets are stored - should contain a SOPS-encrypted file per environment.";
    };
    environments = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Name of the environment.";
          };
          public-keys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "List of AGE public keys that can decrypt this environment.";
          };
          sources = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "List of SOPS-encrypted source files for this environment.";
          };
        };
      });
      default = {};
      description = "Environment-specific secrets configurations.";
    };
    codegen = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Name of the generated code package.";
          };
          directory = lib.mkOption {
            type = lib.types.str;
            description = "Output directory for generated code.";
          };
          language = lib.mkOption {
            type = lib.types.enum [ "typescript" "go" ];
            description = "Programming language for generated code.";
          };
        };
      });
      default = {};
      description = "Code generation settings for secrets.";
    };
  };

  config = lib.mkMerge [
    # Main module config
    (lib.mkIf cfg.enable {
    scripts.ensure-age-key-dev.exec = ''
      KEYFILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

      while read -r line; do
        [[ "$line" == AGE-SECRET-KEY-* ]] || continue
        derived="$(printf '%s\n' "$line" | ${pkgs.age}/bin/age-keygen -y - | awk '{print $NF}')"
        if [[ "$derived" == "$AGE_PUBLIC_KEY_DEV" ]]; then
          [[ "$1" != "-q" ]] && echo "✅ Dev age key found in $KEYFILE"
          exit 0
        fi
      done < "$KEYFILE"

      echo "❌ Error: Dev age key not found in $_f"
      echo "Follow the instructions to add the decryption key:" >&2
      echo "1. Find 'SOPS (Dev)' in 1Password > Dev Vault" >&2
      echo "2. Copy the AGE secret key (password)" >&2
      echo "3. Add it to $KEYFILE (create the file if it doesn't exist)" >&2
      echo "4. Try again" >&2
      exit 1
    '';

    scripts.sops.exec = ''
      # Run preflight check before sops
      ensure-age-key-dev -q || exit 1
      export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
      ${pkgs.sops}/bin/sops "$@"
    '';

    scripts.generate-secrets-schema.exec = ''
      set -e
      to_json() {
        cat "$1" \
         | ${pkgs.yq}/bin/yq \
         | ${pkgs.sops}/bin/sops decrypt --input-type json --output-type json
      }

      INPUT_FILE="$1"
      OUTPUT_FILE="$2"
      LANGUAGE="$3"
      JSON_DATA=$(to_json "$INPUT_FILE")

      case "$LANGUAGE" in
        "typescript")
          echo $JSON_DATA | ${pkgs.bun}/bin/bun x quicktype -o "$OUTPUT_FILE" -
          ;;
        "go")
          echo $JSON_DATA | ${pkgs.bun}/bin/bun x quicktype -o "$OUTPUT_FILE" -
          ;;
        *)
          echo "Unsupported language: $LANGUAGE"
          exit 1
          ;;
        esac
    '';

    scripts.generate-secrets-package.exec = ''
      set -e

      INPUT_DIR="${cfg.input-directory}"
      SHARED_ENV="${cfg.shared-environment}"

      # Configuration baked in at build time as JSON
      ENVIRONMENTS_JSON='${builtins.toJSON cfg.environments}'
      CODEGEN_JSON='${builtins.toJSON cfg.codegen}'

      for ENV_NAME in $(echo "$ENVIRONMENTS_JSON" | ${pkgs.jq}/bin/jq -r 'keys[]'); do
        ENV_CFG=$(echo "$ENVIRONMENTS_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$ENV_NAME" '.[$name]')
        PUBLIC_KEYS=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r '.["public-keys"][]')
        SOURCES=$(echo "$ENV_CFG" | ${pkgs.jq}/bin/jq -r '.sources[]')

        # Decrypt and merge shared and environment-specific secrets
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
    })

    # Test module - only loaded during `devenv test`
    (lib.mkIf (cfg.enable && config.devenv.isTesting)
      (import ./secrets.test.nix { inherit pkgs lib config; })
    )
  ];
}