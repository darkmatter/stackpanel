# ==============================================================================
# generate-docs.nix  (INTERNAL — stackpanel development only)
#
# Regenerates the Fumadocs MDX documentation for stackpanel.* options.
#
# This lives under nix/internal because it is not part of the user-facing
# stackpanel framework. It is only loaded into the devshell of the stackpanel
# repository itself.
#
# It deliberately avoids "cd into apps/ && go run" patterns. We build the
# unified stackpanel binary via nix build and invoke the subcommand on that.
# ==============================================================================
{
  pkgs,
  ...
}:
let
  generateDocsScript = pkgs.writeShellScriptBin "stackpanel-generate-docs" ''
    set -euo pipefail

    ROOT_DIR="''${STACKPANEL_ROOT:-$(pwd)}"
    DOCS_DIR="''${1:-$ROOT_DIR/apps/docs/content/docs}"
    MODULES_DIR="$ROOT_DIR/nix/stackpanel"

    echo "📚 Generating stackpanel options documentation..."
    echo "  Output: $DOCS_DIR"
    echo "  Modules: $MODULES_DIR"

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
      echo "❌ Error: Failed to produce options.json"
      exit 1
    fi

    echo "  Options JSON: $OPTIONS_JSON_FILE"

    echo "  Building stackpanel CLI..."
    CLI=$(nix build --no-link --print-out-paths "$ROOT_DIR#stackpanel")
    STACKPANEL_BIN="$CLI/bin/stackpanel"
    if [ ! -x "$STACKPANEL_BIN" ]; then
      echo "❌ Error: Failed to build stackpanel"
      exit 1
    fi

    mkdir -p "$DOCS_DIR"
    "$STACKPANEL_BIN" gendocs \
      "$OPTIONS_JSON_FILE" \
      "$DOCS_DIR" \
      "$MODULES_DIR"

    echo ""
    echo "✅ Generated documentation in $DOCS_DIR"
  '';
in
{
  config.stackpanel.scripts.generate-docs = {
    description = "INTERNAL: Regenerate Fumadocs MDX from stackpanel option schema";
    exec = ''
      ${generateDocsScript}/bin/stackpanel-generate-docs "$@"
    '';
  };

  config.stackpanel.motd.hints = [
    "Run 'generate-docs' (stackpanel maintainers) to refresh option docs"
  ];
}
