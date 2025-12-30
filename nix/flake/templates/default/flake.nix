# ==============================================================================
# flake.nix
#
# Starter flake template for projects using stackpanel with devenv + flake-parts.
#
# Getting started:
#   1. Run: nix flake init -t github:darkmatter/stackpanel
#   2. Run: direnv allow
#   3. Configure stackpanel in ./nix/stackpanel.nix
# ==============================================================================
{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";
    stackpanel.url = "github:darkmatter/stackpanel";

    # Required for devenv
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";

    # For pure flake evaluation (nix flake check)
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
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
          devenv.shells.default = {
            imports = [ inputs.stackpanel.devenvModules.default ];

            # Stackpanel config (edit ./nix/stackpanel.nix)
            stackpanel = import ./nix/stackpanel.nix;

            # Devenv config (edit ./nix/devenv.nix)
          }
          // (import ./nix/devenv.nix { inherit pkgs; });

          packages.default = pkgs.hello;
        };
    };
}
