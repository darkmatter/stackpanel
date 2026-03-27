# ==============================================================================
# flake.nix
#
# Starter flake template for projects using stackpanel + flake-parts.
#
# Getting started:
#   1. Run: nix flake init -t github:darkmatter/stackpanel
#   2. Run: direnv allow
#   3. Configure stackpanel in ./.stack/config.nix
#
# Shell options:
#   nix develop     # Pure stackpanel shell (fast, reproducible)
#   devenv shell    # Devenv shell with languages/services (if devenv.nix exists)
#
# The flakeModule:
#   - Auto-loads .stack/config.nix
#   - Auto-loads .stack/devenv.nix for additional packages/env
#   - Creates devShells.default via pkgs.mkShell (NOT devenv)
#   - Exposes stackpanelConfig, stackpanelFullConfig, stackpanelPackages
# ==============================================================================
{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "github:darkmatter/stackpanel";

    # For pure flake evaluation (nix flake check)
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.stackpanel.flakeModules.readStackpanelRoot
        inputs.stackpanel.flakeModules.default
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        {
          # The flakeModule auto-loads .stack/config.nix
          # and creates devShells.default automatically when stackpanel.enable = true

          packages.default = pkgs.hello;
        };
    };
}
