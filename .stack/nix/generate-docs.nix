# ==============================================================================
# generate-docs.nix
#
# Stackpanel options documentation generator module.
# Generates MDX documentation from Nix module options using nixosOptionsDoc.
#
# Features:
#   - Transforms stackpanel.* options into structured JSON
#   - Provides 'generate-docs' script for MDX generation
#
# Usage: Run 'generate-docs' in devenv shell to regenerate documentation.
# The Go CLI (apps/stackpanel-go) processes the JSON to create fumadocs-compatible MDX.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Script that builds the docs at runtime to avoid recursive evaluation
  # The options doc generation happens when the script runs, not at eval time
  generateDocsScript = pkgs.writeShellScriptBin "stackpanel-generate-docs" ''
    set -euo pipefail

    ROOT_DIR="''${DEVENV_ROOT:-''${STACKPANEL_ROOT:-$(pwd)}}"
    DOCS_DIR="''${1:-$ROOT_DIR/apps/docs/content/docs}"
    MODULES_DIR="$ROOT_DIR/nix/stackpanel"

    echo "📚 Generating stackpanel options documentation..."
    echo "  Output: $DOCS_DIR"
    echo "  Modules: $MODULES_DIR"

    # Build the options JSON at runtime
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

    echo "  Source: $OPTIONS_JSON/share/doc/nixos/options.json"
    mkdir -p "$DOCS_DIR"

    # Use the Go CLI to generate docs
    cd "$ROOT_DIR/apps/stackpanel-go"
    ${pkgs.go}/bin/go run . gendocs \
      "$OPTIONS_JSON/share/doc/nixos/options.json" \
      "$DOCS_DIR" \
      "$MODULES_DIR"

    echo "✅ Done! Generated documentation in $DOCS_DIR"
  '';
in
{
  # Add a script to generate docs
  config.stackpanel.scripts.generate-docs = {
    exec = ''
      ${generateDocsScript}/bin/stackpanel-generate-docs "$@"
    '';
  };

  # Add MOTD hint
  config.stackpanel.motd.hints = [
    "Run 'generate-docs' to regenerate stackpanel options documentation"
  ];
}
