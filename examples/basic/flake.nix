# ==============================================================================
# flake.nix
#
# Stackpanel example: basic single-app starter.
# Uses flake-parts + the stackpanel flake module.
# ==============================================================================
{
  description = "Stackpanel example: basic single-app starter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
  };

  outputs =
    { self, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake {
      inherit inputs self;
    };
}
