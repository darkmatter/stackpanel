# ==============================================================================
# mkDevShell.nix
#
# Factory function for creating Nix development shells with stackpanel modules.
# Uses lib.evalModules to evaluate a set of NixOS-style modules and produces
# a pkgs.mkShell derivation with packages, hooks, and environment variables.
#
# Usage:
#   mkDevShell { inherit pkgs; } {
#     modules = [ ./my-module.nix ];
#     specialArgs = { myArg = "value"; };
#     extraPackages = [ pkgs.jq ];  # additional packages to include
#   }
#
# The resulting shell includes:
#   - packages and nativeBuildInputs from devshell config
#   - environment variable exports
#   - shell hooks (before, main, after phases)
#   - passthru with devshellConfig and moduleConfig for introspection
# ==============================================================================
{ pkgs }:
{
  modules ? [ ],
  specialArgs ? { },
  extraPackages ? [ ],
}:
let
  lib = pkgs.lib;

  # Import serialization helpers for JSON-safe config
  serializeLib = import ../../stackpanel/lib/serialize.nix { inherit lib; };

  # Helper to serialize a package derivation to JSON-safe format
  serializePackage =
    pkg:
    if builtins.isAttrs pkg then
      {
        name = pkg.pname or pkg.name or "unknown";
        version = pkg.version or "";
        attrPath = pkg.meta.mainProgram or pkg.pname or pkg.name or "";
        source = "devshell";
      }
    else if builtins.isString pkg then
      {
        name = pkg;
        version = "";
        attrPath = pkg;
        source = "devshell";
      }
    else
      {
        name = "unknown";
        version = "";
        attrPath = "";
        source = "devshell";
      };

  evaluated = lib.evalModules {
    modules = [
      # Always-on stackpanel core
      ../../stackpanel/core/default.nix
    ]
    ++ modules;
    specialArgs = {
      inherit pkgs;
    }
    // specialArgs;
  };

  # Access stackpanel.devshell config
  cfg = evaluated.config.stackpanel.devshell;

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') cfg.env
  );

  shellHook = lib.concatStringsSep "\n\n" (
    lib.flatten [
      # mkShell needs env exports here
      envExports
      cfg.hooks.before
      cfg.hooks.main
      cfg.hooks.after
    ]
  );
  # Pre-compute serialized packages for fast access
  # This combines devshell packages with user-installed packages
  devshellPackages = cfg.packages or [ ];
  commandPkgs = cfg._commandPkgs or [ ];
  allDevshellPackages = devshellPackages ++ commandPkgs;
  serializedDevshellPackages = map serializePackage allDevshellPackages;

  # User packages from .stackpanel/data/packages.nix (already serialized)
  userPackagesCfg =
    evaluated.config.stackpanel.userPackages or {
      enable = false;
      serialized = [ ];
    };
  userPackagesSerialized =
    if userPackagesCfg.enable or false then userPackagesCfg.serialized or [ ] else [ ];

  # Combined serialized packages
  allSerializedPackages = serializedDevshellPackages ++ userPackagesSerialized;
in
pkgs.mkShell {
  packages = cfg.packages ++ (cfg._commandPkgs or [ ]) ++ extraPackages;
  nativeBuildInputs = cfg.nativeBuildInputs;
  buildInputs = cfg.buildInputs;
  shellHook = shellHook;

  passthru = {
    devshellConfig = cfg;
    moduleConfig = evaluated.config;
    extraPackages = extraPackages;
    # Full stackpanel config (may contain non-serializable values)
    stackpanelConfig = evaluated.config.stackpanel;
    # JSON-safe version for CLI/agent consumption
    stackpanelSerializable = serializeLib.filterSerializable evaluated.config.stackpanel;
    # Pre-serialized packages for fast access (avoids slow nix eval at runtime)
    # Usage: nix eval .#stackpanelPackages --json
    stackpanelPackages = allSerializedPackages;
  };
}
