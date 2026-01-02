# ==============================================================================
# flake.nix (native template)
#
# Minimal stackpanel setup using native Nix shells (no devenv dependency).
# This is ideal for projects that want stackpanel features but prefer
# standard `nix develop` workflows.
#
# Getting started:
#   1. Run: nix flake init -t github:darkmatter/stackpanel#native
#   2. Run: nix develop --impure
#   3. Configure stackpanel in ./.stackpanel/config.nix
# ==============================================================================
{
  description = "My project with stackpanel (native shell)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "github:darkmatter/stackpanel";

    # For pure flake evaluation (nix flake check)
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.stackpanel.flakeModules.readStackpanelRoot
        inputs.stackpanel.flakeModules.native
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        {
          # Stackpanel configuration
          # The flakeModules.native creates devShells.default automatically
          stackpanel = import ./.stackpanel/config.nix // {
            enable = true;
          };

          # Your project's packages
          packages.default = pkgs.hello;
        };
    };
}
