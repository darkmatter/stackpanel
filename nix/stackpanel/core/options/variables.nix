{
  lib,
  config,
  ...
}:
let
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
