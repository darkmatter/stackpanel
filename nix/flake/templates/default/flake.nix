# ==============================================================================
# flake.nix
#
# Starter flake template for projects using stackpanel.
# Prelude (motd / menu / docs) arrives transitively — no extra input needed.
# Disable packages/banner in .stack/config.nix: prelude.enable = false;
# ==============================================================================
{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    stackpanel.url = "github:darkmatter/stackpanel";
  };

  outputs =
    { self, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake {
      inherit inputs self;

      perSystem =
        { pkgs, ... }:
        {
          packages.hello = pkgs.hello;
        };
    };
}
