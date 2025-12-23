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
{ pkgs
, lib
, config
, options
, ...
}:

let
  # Get stackpanel options from the evaluated module system
  stackpanelOptions = options.stackpanel or {};

  # Transform option declarations to readable paths
  transformOptions = opt: opt // {
    declarations = map (decl:
      let
        declStr = toString decl;
        # Try to make paths relative and linkable
        relativePath =
          if lib.hasPrefix (toString ../.) declStr
          then lib.removePrefix (toString ../. + "/") declStr
          else if lib.hasPrefix "/nix/store" declStr
          then builtins.baseNameOf (builtins.dirOf declStr) + "/" + builtins.baseNameOf declStr
          else declStr;
      in {
        name = relativePath;
        url =
          if lib.hasPrefix "modules/" relativePath
          then "https://github.com/darkmatter/stackpanel/blob/main/nix/${relativePath}"
          else null;
      }
    ) (opt.declarations or []);
  };

  # Filter to only stackpanel.* options
  filterStackpanelOptions =
    lib.filterAttrs (name: _: lib.hasPrefix "stackpanel" name);

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
    MODULES_DIR="$ROOT_DIR/nix/modules"
    OPTIONS_JSON="${optionsDoc.optionsJSON}/share/doc/nixos/options.json"

    echo "📚 Generating stackpanel options documentation..."
    echo "  Source: $OPTIONS_JSON"
    echo "  Output: $DOCS_DIR"
    echo "  Modules: $MODULES_DIR"

    mkdir -p "$DOCS_DIR"

    # Use the Go CLI to generate docs
    cd "$ROOT_DIR/apps/cli"
    ${pkgs.go}/bin/go run . gendocs \
      "$OPTIONS_JSON" \
      "$DOCS_DIR" \
      "$MODULES_DIR"

    echo "✅ Done! Generated documentation in $DOCS_DIR"
  '';

in {
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

  # Add hint about docs generation
  stackpanel.motd.hints = lib.mkIf (config.stackpanel.enable or false) [
    "Run 'generate-docs' to regenerate options documentation"
  ];
}
