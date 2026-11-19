# Run the external-module template's own flake check with the already locked
# inputs. No getFlake, nested nix command, network resolution or IFD needed.
{
  localInputs,
  localFlake,
  system,
}:
let
  fixture = ../../../flake/templates/_test-fixtures/external-module;
  inputs = {
    inherit (localInputs) nixpkgs flake-parts;
    stackpanel = localFlake;
    test-module = (import (fixture + "/test-module/flake.nix")).outputs { };
    self = {
      outPath = fixture;
      inherit inputs;
      inherit (outputs) legacyPackages packages nixosModules;
    };
  };
  outputs = (import (fixture + "/flake.nix")).outputs inputs;
in
outputs.checks.${system}.external-module
