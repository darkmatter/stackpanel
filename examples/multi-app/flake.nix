# ==============================================================================
# flake.nix
#
# Stackpanel example: multi-app monorepo.
# Uses flake-parts + the stackpanel flake module.
# ==============================================================================
{
  description = "Stackpanel example: multi-app monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "github:darkmatter/stackpanel";
  };

  outputs =
    { self, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake {
      inherit inputs self;
    };
}
