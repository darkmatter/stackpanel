{
  lib ? import <nixpkgs/lib>,
}:
let
  core = import ./envvars/helpers.nix { inherit lib; };
  sections = import ./envvars/sections.nix {
    inherit lib;
    inherit (core) mkEnvVar;
    inherit (core) categories;
  };
in
core
// sections
// import ./envvars/derived.nix {
  inherit lib;
  inherit (core) categories;
  inherit sections;
}
