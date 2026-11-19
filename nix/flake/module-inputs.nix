# Built-in integrations use Stackpanel's pins unless the project supplies its
# own. Do not pass these transitive dependencies to module/hook discovery.
localFlake: inputs:
builtins.intersectAttrs {
  nixpkgs = null;
  nix2container = null;
  prelude = null;
} (if localFlake == null then { } else localFlake.inputs or { })
// inputs
