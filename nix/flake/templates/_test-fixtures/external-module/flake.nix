{
  description = "Integration test: external Stackpanel module, overlay, adapter and UI bundle";
  inputs = {
    stackpanel.url = "github:darkmatter/stackpanel";
    nixpkgs.follows = "stackpanel/nixpkgs";
    flake-parts.follows = "stackpanel/flake-parts";
    test-module.url = "path:./test-module";
  };
  outputs =
    inputs:
    inputs.stackpanel.lib.mkFlake {
      inherit inputs;
      perSystem = { pkgs, system, ... }: {
        checks.external-module = import ./check.nix { inherit inputs pkgs system; };
      };
    };
}
