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
    type = types.attrsOf types.package;
    default = { };
    description = ''
      Output derivations to expose.
      
      These will be available as:
        - `nix build .#<name>` (via flake)
        - `devenv outputs.<name>` (via devenv)
      
      Example:
        stackpanel.outputs = {
          my-docs = pkgs.runCommand "docs" {} "...";
          my-script = pkgs.writeShellScriptBin "foo" "...";
        };
    '';
    example = lib.literalExpression ''
      {
        docs-json = optionsDoc.optionsJSON;
        docs-md = optionsDoc.optionsCommonMark;
      }
    '';
  };
}
