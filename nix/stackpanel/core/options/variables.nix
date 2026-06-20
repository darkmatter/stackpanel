{
  lib,
  config,
  ...
}:
let
  # Shared schema/docs for the variable registry. Kept in a part file because
  # backend and codegen modules also need the helper functions.
  defs = import ./variables-parts/definitions.nix { inherit lib config; };
in
{
  options.stackpanel.variables = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule defs.variableModule);
    default = { };
    inherit (defs) description;
    inherit (defs) example;
  };
}
