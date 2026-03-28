# ==============================================================================
# flake.nix
#
# Minimal flake template for stackpanel.
# Uses standard Nix flake structure with flake-utils.
#
# Getting started:
#   1. Run: nix flake init -t git+ssh://git@github.com/darkmatter/stackpanel#minimal
#   2. Run: direnv allow
#   3. Configure stackpanel in ./.stack/config.nix
# ==============================================================================
{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    stackpanel.url = "git+ssh://git@github.com/darkmatter/stackpanel";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      stackpanel,
      ...
    }@inputs:
    # Simple usage: just call mkFlake
    stackpanel.lib.mkFlake { inherit inputs self; }
    # Merge with your own outputs
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.hello; # Replace with your package
      }
    );
}
