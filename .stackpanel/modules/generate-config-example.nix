# ==============================================================================
# generate-config-example.nix
#
# Generates an annotated config.nix.example with comments from option descriptions.
#
# Features:
#   - Extracts option descriptions from Nix module system
#   - Generates config.nix.example with inline documentation
#   - Optional flag to control comment inclusion (--no-comments)
#   - Outputs both commented and minimal versions
#
# Usage:
#   generate-config-example              # Full annotated version
#   generate-config-example --no-comments # Minimal version without comments
#   generate-config-example --output <path>  # Custom output path
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;

  # Script that generates config.nix.example with option descriptions
  generateConfigExampleScript = pkgs.writeShellScriptBin "stackpanel-generate-config-example" ''
    set -euo pipefail

    ROOT_DIR="''${DEVENV_ROOT:-''${STACKPANEL_ROOT:-$(pwd)}}"
    OUTPUT_PATH="$ROOT_DIR/.stackpanel/config.nix.example"
    INCLUDE_COMMENTS=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-comments)
          INCLUDE_COMMENTS=false
          shift
          ;;
        --output)
          OUTPUT_PATH="$2"
          shift 2
          ;;
        -o)
          OUTPUT_PATH="$2"
          shift 2
          ;;
        --help|-h)
          echo "Usage: generate-config-example [OPTIONS]"
          echo ""
          echo "Generate an annotated config.nix.example with option descriptions."
          echo ""
          echo "Options:"
          echo "  --no-comments        Generate minimal version without documentation comments"
          echo "  --output, -o PATH    Custom output path (default: .stackpanel/config.nix.example)"
          echo "  --help, -h           Show this help message"
          exit 0
          ;;
        *)
          echo "Unknown option: $1"
          echo "Run with --help for usage information"
          exit 1
          ;;
      esac
    done

    echo "📝 Generating config.nix.example with option descriptions..."
    echo "  Output: $OUTPUT_PATH"
    echo "  Comments: $INCLUDE_COMMENTS"

    # Build the options JSON at runtime to avoid recursive evaluation
    echo "  Building options documentation..."
    OPTIONS_JSON=$(nix build --impure --no-link --print-out-paths \
      --expr 'let
        pkgs = import <nixpkgs> {};
        lib = pkgs.lib;
        evalResult = lib.evalModules {
          modules = [
            '"$ROOT_DIR"'/nix/stackpanel/core/options
            { _module.args = { inherit pkgs; }; stackpanel.enable = true; }
          ];
          specialArgs = { inherit lib; };
        };
        transformOptions = opt: opt // {
          declarations = map (decl:
            let declStr = toString decl; in
            { name = declStr; url = null; }
          ) (opt.declarations or []);
        };
        optionsDoc = pkgs.nixosOptionsDoc {
          options = builtins.removeAttrs (evalResult.options.stackpanel or {}) ["_module"];
          inherit transformOptions;
          warningsAreErrors = false;
        };
      in optionsDoc.optionsJSON'
    )

    OPTIONS_JSON_FILE="$OPTIONS_JSON/share/doc/nixos/options.json"

    if [ ! -f "$OPTIONS_JSON_FILE" ]; then
      echo "❌ Error: Failed to generate options JSON"
      exit 1
    fi

    echo "  Options JSON: $OPTIONS_JSON_FILE"

    # Read current config.nix as reference for structure
    CURRENT_CONFIG="$ROOT_DIR/.stackpanel/config.nix"

    mkdir -p "$(dirname "$OUTPUT_PATH")"

    # Generate annotated config using Go CLI
    cd "$ROOT_DIR/apps/stackpanel-go"

    GO_ARGS=(
      config
      generate-example
      --options-json "$OPTIONS_JSON_FILE"
      --output "$OUTPUT_PATH"
    )

    if [ "$INCLUDE_COMMENTS" = "false" ]; then
      GO_ARGS+=(--no-comments)
    fi

    if [ -f "$CURRENT_CONFIG" ]; then
      GO_ARGS+=(--current-config "$CURRENT_CONFIG")
    fi

    ${pkgs.go}/bin/go run . "''${GO_ARGS[@]}"

    echo ""
    echo "✅ Generated: $OUTPUT_PATH"

    if [ "$INCLUDE_COMMENTS" = "true" ]; then
      echo ""
      echo "💡 Tips:"
      echo "  • Review the generated file for documentation on all available options"
      echo "  • Copy sections you need to your config.nix"
      echo "  • Run with --no-comments for a minimal example without documentation"
    else
      echo ""
      echo "💡 To generate with inline documentation, run: generate-config-example"
    fi
  '';
in
{
  # Add script to generate config.nix.example
  config.stackpanel.scripts.generate-config-example = lib.mkIf cfg.enable {
    description = "Generate annotated config.nix.example with option descriptions";
    exec = ''
      ${generateConfigExampleScript}/bin/stackpanel-generate-config-example "$@"
    '';
  };

  # Add MOTD hint
  config.stackpanel.motd.hints = lib.mkIf cfg.enable [
    "Run 'generate-config-example' to create config.nix.example with inline docs"
  ];
}
