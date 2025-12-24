# Global Development Services for `nix develop`
#
# This library provides the same global singleton services as the devenv module,
# but compatible with standard `nix develop` (flake devShells / mkShell).
#
# Usage in flake.nix:
#
#   {
#     inputs.stackpanel.url = "github:darkmatter/stackpanel";
#     inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
#
#     outputs = { self, nixpkgs, stackpanel, ... }:
#       let
#         system = "x86_64-linux";
#         pkgs = nixpkgs.legacyPackages.${system};
#         devServices = stackpanel.lib.mkDevShell pkgs {
#           projectName = "myproject";
#           postgres = {
#             enable = true;
#             databases = ["myapp" "myapp_test"];
#           };
#           redis.enable = true;
#           minio.enable = true;
#           caddy.enable = true;
#         };
#       in {
#         devShells.${system}.default = pkgs.mkShell (devServices // {
#           # Add your own packages
#           packages = devServices.packages ++ [ pkgs.nodejs ];
#         });
#       };
#   }
#
# Or merge with an existing mkShell:
#
#   devShells.default = pkgs.mkShell {
#     packages = [ pkgs.nodejs ] ++ devServices.packages;
#     shellHook = ''
#       ${devServices.shellHook}
#       echo "My custom setup"
#     '';
#   } // { inherit (devServices) env; };
#
{
  pkgs,
  lib ? pkgs.lib,
}: let
  # Shared core implementation for global services (used by both devenv and mkShell)
  globalServices = import ./core/global-services.nix {inherit pkgs lib;};

  # Port computation utilities
  portsLib = import ./core/ports.nix { inherit lib; };

  # Default configuration - services can be added by including them here
  defaultConfig = {
    projectName = "default";
    ports = {};

    # Each service follows the pattern:
    # serviceName = {
    #   enable = false;
    #   ...options specific to that service
    # };
    postgres = {
      enable = false;
      databases = null; # Will default to [projectName] if null
      port = 5432;
      package = pkgs.postgresql_17;
    };

    redis = {
      enable = false;
      port = 6379;
      package = pkgs.redis;
    };

    minio = {
      enable = false;
      port = 9000;
      consolePort = 9001;
      package = pkgs.minio;
    };

    caddy = {
      enable = false;
      sites = {};
      # Step CA integration (optional)
      stepEnabled = false;
      stepCaUrl = "";
      stepCaFingerprint = "";
    };
  };

  # Deep merge helper
  mergeConfig = defaults: user:
    lib.recursiveUpdate defaults user;
in {
  # Main entry point: creates shell attributes for mkShell
  mkDevShell = userConfig: let
    cfg = mergeConfig defaultConfig userConfig;
    gs = globalServices.mkGlobalServices {
      projectName = cfg.projectName;
      ports = cfg.ports;
      postgres = cfg.postgres;
      redis = cfg.redis;
      minio = cfg.minio;
      caddy = cfg.caddy;
    };
  in {
    inherit (gs) packages shellHook env services shell;
  };

  # Expose port computation utilities for mkShell users
  # Usage: stackpanelLib.ports.computeBasePort { name = "myproject"; }
  ports = portsLib;
}
