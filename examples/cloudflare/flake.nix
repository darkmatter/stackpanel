# ==============================================================================
# flake.nix
#
# Stackpanel example: Cloudflare edge deployment.
# Uses flake-parts + the stackpanel flake module.
# ==============================================================================
{
  description = "Stackpanel example: Cloudflare edge deployment";

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
