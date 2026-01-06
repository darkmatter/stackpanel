# ==============================================================================
# docs/generate.nix
#
# Stackpanel options documentation generator module.
# Generates MDX documentation from Nix module options using nixosOptionsDoc.
#
# Features:
#   - Transforms stackpanel.* options into structured JSON
#   - Provides 'generate-docs' script for MDX generation
#   - Outputs: stackpanel-docs-options-json, stackpanel-docs-options-md
#
# Usage: Run 'generate-docs' in devenv shell to regenerate documentation.
# The Go CLI (apps/stackpanel-go) processes the JSON to create fumadocs-compatible MDX.
# ==============================================================================
# Stackpanel options documentation generator
#
# This module is imported by devenv to generate documentation.
# It uses devenv's evaluation context to access the full options tree.
#
# Add to devenv.nix:
#   imports = [ ./nix/docs ];
#
# Then access via:
#   nix build .#devenv-docs-options-json
#
{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  # Get stackpanel options from the evaluated module system
  stackpanelOptions = options.stackpanel or { };

  # Transform option declarations to readable paths
  transformOptions =
    opt:
    opt
    // {
      declarations = map (
        decl:
        let
          declStr = toString decl;
          # Try to make paths relative and linkable
          relativePath =
            if lib.hasPrefix (toString ../.) declStr then
              lib.removePrefix (toString ../. + "/") declStr
            else if lib.hasPrefix "/nix/store" declStr then
              builtins.baseNameOf (builtins.dirOf declStr) + "/" + builtins.baseNameOf declStr
            else
              declStr;
        in
        {
          name = relativePath;
          url =
            if lib.hasPrefix "modules/" relativePath then
              "https://github.com/darkmatter/stackpanel/blob/main/nix/${relativePath}"
            else
              null;
        }
      ) (opt.declarations or [ ]);
    };

  # Filter to only stackpanel.* options
  filterStackpanelOptions = lib.filterAttrs (name: _: lib.hasPrefix "stackpanel" name);

  # Generate documentation using nixosOptionsDoc
  optionsDoc = pkgs.nixosOptionsDoc {
    options = builtins.removeAttrs stackpanelOptions [ "_module" ];
    inherit transformOptions;
    warningsAreErrors = false;
  };

  # Script to generate MDX docs
  generateDocsScript = pkgs.writeShellScriptBin "stackpanel-generate-docs" ''
    set -euo pipefail

    ROOT_DIR="''${DEVENV_ROOT:-$(pwd)}"
    DOCS_DIR="''${1:-$ROOT_DIR/apps/docs/content/docs}"
    MODULES_DIR="$ROOT_DIR/nix/stackpanel"
    OPTIONS_JSON="${optionsDoc.optionsJSON}/share/doc/nixos/options.json"

    echo "📚 Generating stackpanel options documentation..."
    echo "  Source: $OPTIONS_JSON"
    echo "  Output: $DOCS_DIR"
    echo "  Modules: $MODULES_DIR"

    mkdir -p "$DOCS_DIR"

    # Use the Go CLI to generate docs
    cd "$ROOT_DIR/apps/stackpanel-go"
    ${pkgs.go}/bin/go run . gendocs \
      "$OPTIONS_JSON" \
      "$DOCS_DIR" \
      "$MODULES_DIR"

    echo "✅ Done! Generated documentation in $DOCS_DIR"
  '';
in
{
  # Add to devenv outputs
  outputs = {
    stackpanel-docs-options-json = optionsDoc.optionsJSON;
    stackpanel-docs-options-md = optionsDoc.optionsCommonMark;
  };

  # Add a script to generate docs
  scripts.generate-docs = {
    description = "Generate stackpanel options documentation for fumadocs";
    exec = ''
      ${generateDocsScript}/bin/stackpanel-generate-docs "$@"
    '';
  };

  # NOTE: MOTD hints have been moved to .stackpanel/config.nix
  # since stackpanel options are no longer available in devenv context
}
