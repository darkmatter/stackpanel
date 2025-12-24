# mkDevShell - Development Shell Builder for `nix develop`
#
# Creates shell attributes for mkShell, providing the same global services
# available in devenv but for standard flake-based development.
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
#         devShell = stackpanel.lib.mkDevShell pkgs {
#           projectName = "myproject";
#           postgres.enable = true;
#         };
#       in {
#         devShells.${system}.default = devShell.shell;
#       };
#   }
#
{
  pkgs,
  lib ? pkgs.lib,
}: let
  # Import shared libraries
  portsLib = import ./core/ports.nix { inherit lib; };
  globalServices = import ./core/global-services.nix { inherit pkgs lib; };

  # Default configuration
  defaultConfig = {
    projectName = "default";
    stateDir = ".stackpanel/state";
    genDir = ".stackpanel/gen";
    dataDir = ".stackpanel";
    ports = {};
    postgres = { enable = false; databases = null; port = null; };
    redis = { enable = false; port = null; };
    minio = { enable = false; port = null; consolePort = null; };
    caddy = { enable = false; sites = {}; };
  };

  # Deep merge helper
  mergeConfig = defaults: user:
    lib.recursiveUpdate defaults user;

in {
  # Main entry point: creates shell attributes for mkShell
  mkDevShell = userConfig: let
    cfg = mergeConfig defaultConfig userConfig;

    # Compute ports
    basePort = portsLib.computeBasePort {
      name = cfg.projectName;
      minPort = cfg.ports.minPort or portsLib.defaults.minPort;
      portRange = cfg.ports.portRange or portsLib.defaults.portRange;
      modulus = cfg.ports.modulus or portsLib.defaults.modulus;
    };

    # Build global services
    gs = globalServices.mkGlobalServices {
      projectName = cfg.projectName;
      ports = cfg.ports;
      postgres = cfg.postgres;
      redis = cfg.redis;
      minio = cfg.minio;
      caddy = cfg.caddy;
    };

    # Shell hook for directory setup
    dirSetupHook = ''
      # Stackpanel shell initialization
      export STACKPANEL_ROOT="''${STACKPANEL_ROOT:-$PWD}"
      export STACKPANEL_STATE_DIR="''${STACKPANEL_STATE_DIR:-$STACKPANEL_ROOT/${cfg.stateDir}}"
      export STACKPANEL_GEN_DIR="''${STACKPANEL_GEN_DIR:-$STACKPANEL_ROOT/${cfg.genDir}}"
      export STACKPANEL_DATA_DIR="''${STACKPANEL_DATA_DIR:-$STACKPANEL_ROOT/${cfg.dataDir}}"
      mkdir -p "$STACKPANEL_STATE_DIR" "$STACKPANEL_GEN_DIR"

      export STACKPANEL_BASE_PORT="${toString basePort}"
      export STACKPANEL_PROJECT_NAME="${cfg.projectName}"
    '';

    allShellHook = dirSetupHook + "\n" + gs.shellHook;

    allEnv = gs.env // {
      STACKPANEL_BASE_PORT = toString basePort;
      STACKPANEL_PROJECT_NAME = cfg.projectName;
    };

  in {
    packages = gs.packages;
    shellHook = allShellHook;
    env = allEnv;
    services = gs.services;

    # Computed values
    computed = {
      inherit basePort;
      inherit (cfg) projectName;
    };

    # Ready-to-use mkShell
    shell = pkgs.mkShell ({
      packages = gs.packages;
      shellHook = allShellHook;
    } // allEnv);

    # For compatibility
    enterShell = allShellHook;
  };

  # Expose port computation utilities
  ports = portsLib;
}
