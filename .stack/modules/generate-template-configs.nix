# ==============================================================================
# generate-template-configs.nix
#
# Regenerates checked-in starter template config.nix files from Stackpanel option
# metadata so template configs stay in sync with the option schema.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;

  generateTemplateConfigsScript = pkgs.writeShellScriptBin "stackpanel-generate-template-configs" ''
    set -euo pipefail

    ROOT_DIR="''${STACKPANEL_ROOT:-$(pwd)}"
    TEMPLATE_ROOT="$ROOT_DIR/nix/flake/templates"

    echo "Generating template config.nix files from option metadata..."
    echo "  Templates: default, minimal"
    echo "  Template root: $TEMPLATE_ROOT"

    echo "  Building options documentation..."
    OPTIONS_JSON=$(nix build --impure --no-link --print-out-paths \
      --expr 'let
        pkgs = import <nixpkgs> {};
        lib = pkgs.lib;
        mkOptionsDoc = import '"$ROOT_DIR"'/nix/stackpanel/lib/options-doc.nix { inherit pkgs lib; };
      in (mkOptionsDoc {}).optionsJSON'
    )
    OPTIONS_JSON_FILE="$OPTIONS_JSON/share/doc/nixos/options.json"

    if [ ! -f "$OPTIONS_JSON_FILE" ]; then
      echo "Error: Failed to generate options JSON"
      exit 1
    fi

    echo "  Options JSON: $OPTIONS_JSON_FILE"

    echo "  Building stackpanel CLI..."
    CLI=$(nix build --no-link --print-out-paths "$ROOT_DIR#stackpanel")
    STACKPANEL_BIN="$CLI/bin/stackpanel"

    if [ ! -x "$STACKPANEL_BIN" ]; then
      echo "Error: Failed to build stackpanel CLI"
      exit 1
    fi

    generate_template() {
      local template="$1"
      local mode="$2"
      local output_path="$TEMPLATE_ROOT/$template/.stack/config.nix"

      mkdir -p "$(dirname "$output_path")"

      echo "  Generating $template -> $output_path"
      if [ "$mode" = "minimal" ]; then
        "$STACKPANEL_BIN" config generate-example \
          --options-json "$OPTIONS_JSON_FILE" \
          --output "$output_path" \
          --template-config \
          --no-comments
      else
        "$STACKPANEL_BIN" config generate-example \
          --options-json "$OPTIONS_JSON_FILE" \
          --output "$output_path" \
          --template-config
      fi
    }

    generate_template default annotated
    generate_template minimal minimal

    echo "  Formatting generated configs..."
    ${pkgs.nixfmt-rfc-style}/bin/nixfmt \
      "$TEMPLATE_ROOT/default/.stack/config.nix" \
      "$TEMPLATE_ROOT/minimal/.stack/config.nix"

    echo ""
    echo "Generated template config.nix files"
    echo "  - nix/flake/templates/default/.stack/config.nix"
    echo "  - nix/flake/templates/minimal/.stack/config.nix"
    echo ""
    echo "Review and commit the regenerated files with the option changes."
  '';
in
{
  config = lib.mkIf cfg.enable {
    stackpanel.scripts.generate-template-configs = {
      description = "Regenerate default/minimal template config.nix from option metadata";
      exec = ''
        ${generateTemplateConfigsScript}/bin/stackpanel-generate-template-configs "$@"
      '';
      timeout = 1800;
    };

    stackpanel.motd.hints = [
      "Run 'generate-template-configs' to regenerate default/minimal config.nix from option metadata"
    ];
  };
}
