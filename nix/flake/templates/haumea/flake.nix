# ==============================================================================
# flake.nix
#
# Starter flake template for projects using stackpanel with tree config.
# ==============================================================================
{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "github:darkmatter/stackpanel";
    # Tree config (`.stack/config/`) is loaded by haumea; reuse stackpanel's pin.
    haumea.follows = "stackpanel/haumea";
  };

  outputs =
    { self, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake {
      inherit inputs self;

      perSystem =
        { pkgs, ... }:
        {
          packages.default = pkgs.hello;
        };
    };
}
