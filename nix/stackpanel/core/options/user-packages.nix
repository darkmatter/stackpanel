# ==============================================================================
# user-packages.nix
#
# User-installed packages module - reads packages from .stackpanel/data/packages.nix
#
# This module allows users to add packages via the Stackpanel UI. Packages are
# stored in .stackpanel/data/packages.nix as a list of attribute paths, and
# this module resolves them to actual packages from nixpkgs.
#
# Data file format (.stackpanel/data/packages.nix):
#   [
#     "ripgrep"
#     "jq"
#     "htop"
#   ]
#
# The module reads this file and adds the packages to stackpanel.devshell.packages.
#
# Note: pkgs is optional. Package resolution only happens when pkgs is available.
# When pkgs is not available (e.g., flake-parts top-level), resolved/serialized
# will be empty lists.
# ==============================================================================
{
  lib,
  config,
  ...
}@args:
let
  # Check if pkgs was provided without triggering a lookup error
  hasPkgs = args ? pkgs;
  pkgs = args.pkgs or null;
  cfg = config.stackpanel.userPackages;

  # Path to the user packages data file
  dataDir = config.stackpanel.dirs.home or ".stackpanel";
  packagesFile = "${builtins.getEnv "STACKPANEL_ROOT"}/${dataDir}/data/packages.nix";

  # Read the packages file if it exists
  # Returns a list of attribute path strings
  userPackageAttrs =
    if builtins.pathExists packagesFile then
      let
        imported = import packagesFile;
      in
      if builtins.isList imported then imported else [ ]
    else
      [ ];

  # Resolve an attribute path string to a package from pkgs
  # e.g., "ripgrep" -> pkgs.ripgrep
  # e.g., "nodePackages.typescript" -> pkgs.nodePackages.typescript
  resolvePackage =
    attrPath:
    let
      parts = lib.splitString "." attrPath;
      resolved = lib.attrByPath parts null pkgs;
    in
    if resolved != null then resolved else null;

  # Resolve all user packages, filtering out any that couldn't be resolved
  resolvedPackages =
    if hasPkgs then lib.filter (p: p != null) (map resolvePackage userPackageAttrs) else [ ];

  # Create serializable package info for the config JSON
  serializePackage =
    attrPath:
    let
      pkg = resolvePackage attrPath;
    in
    if pkg != null then
      {
        name = pkg.pname or pkg.name or attrPath;
        version = pkg.version or "";
        attrPath = attrPath;
        source = "user"; # Mark as user-installed
      }
    else
      {
        name = attrPath;
        version = "";
        attrPath = attrPath;
        source = "user";
        error = "Package not found in nixpkgs";
      };

  serializedUserPackages = if hasPkgs then map serializePackage userPackageAttrs else [ ];
in
{
  options.stackpanel.userPackages = {
    enable = lib.mkEnableOption "user-installed packages from .stackpanel/data/packages.nix" // {
      default = true;
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = userPackageAttrs;
      readOnly = true;
      description = "List of user-installed package attribute paths (read from packages.nix)";
    };

    resolved = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      readOnly = true;
      description = ''
        Resolved package derivations from user package list.

        Only populated when pkgs is available. Empty list otherwise.
      '';
    };

    serialized = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      description = ''
        Serialized package info for config JSON.

        Only populated when pkgs is available. Empty list otherwise.
      '';
    };
  };

  config = lib.mkMerge [
    # Always set computed values (may be empty if pkgs not available)
    {
      stackpanel.userPackages.resolved = resolvedPackages;
      stackpanel.userPackages.serialized = serializedUserPackages;
    }

    # Add resolved user packages to devshell when enabled and pkgs available
    (lib.mkIf (cfg.enable && hasPkgs) {
      stackpanel.devshell.packages = resolvedPackages;
    })
  ];
}
