# ==============================================================================
# flake.nix
#
# Minimal flake template for stackpanel without flake-parts.
# Uses standard Nix flake structure with devenv.
#
# Getting started:
#   1. Run: nix flake init -t github:darkmatter/stackpanel#minimal
#   2. Run: direnv allow
#   3. Configure stackpanel in ./.stack/config.nix
# ==============================================================================
{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    stackpanel.url = "github:darkmatter/stackpanel";
  };

  outputs =
    {
      self,
      nixpkgs,
      devenv,
      stackpanel,
      ...
    }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              # Import stackpanel module
              stackpanel.devenvModules.default

              # Your configuration
              (
                {
                  pkgs,
                  lib,
                  config,
                  ...
                }:
                {
                  # Stackpanel config (edit ./.stack/config.nix)
                  stackpanel =
                    let
                      raw = import ./.stack/config.nix;
                      cfg =
                        if builtins.isFunction raw then
                          raw {
                            inherit pkgs lib config;
                            inherit inputs self;
                          }
                        else
                          raw;
                    in
                    cfg;

                  # Packages
                  packages = with pkgs; [
                    git
                    jq
                  ];

                  # Languages
                  # languages.typescript.enable = true;
                  # languages.go.enable = true;

                  # Environment variables
                  env = {
                    # DATABASE_URL = "postgres://localhost:5432/myapp";
                  };

                  # Shell hook
                  enterShell = ''
                    echo "Welcome to the dev environment!"
                  '';

                  # Processes (run with `devenv up`)
                  # processes.server.exec = "bun run dev";
                }
              )
            ];
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.hello; # Replace with your package
        }
      );
    };
}
