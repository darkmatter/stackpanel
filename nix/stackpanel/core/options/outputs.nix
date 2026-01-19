# ==============================================================================
# outputs.nix
#
# Output derivations that should be exposed via the flake or devenv.
#
# These are Nix derivations that can be built with `nix build .#<name>`.
# The adapter (devenv.nix or flake) is responsible for exposing these.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  types = lib.types;
in
{
  options.stackpanel.outputs = lib.mkOption {
    type = types.attrsOf (types.either types.package (types.attrsOf types.package));
    default = { };
    description = ''
      Output derivations to expose.
      
      These will be available as:
        - `nix build .#<name>` (via flake) - for direct packages
        - `nix run .#<group>.<name>` (via flake) - for grouped packages (like scripts)
        - `devenv outputs.<name>` (via devenv)
      
      Example:
        stackpanel.outputs = {
          my-docs = pkgs.runCommand "docs" {} "...";
          my-script = pkgs.writeShellScriptBin "foo" "...";
          # Grouped packages (available via nix run .#scripts.<name>)
          scripts = { foo = pkgs.writeShellScriptBin "foo" "..."; };
        };
    '';
    example = lib.literalExpression ''
      {
        docs-json = optionsDoc.optionsJSON;
        docs-md = optionsDoc.optionsCommonMark;
        scripts = { my-script = pkgs.writeShellScriptBin "test" "echo hello"; };
      }
    '';
  };
}
