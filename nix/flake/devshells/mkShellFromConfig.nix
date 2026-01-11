# ==============================================================================
# mkShellFromConfig.nix
#
# Creates a nix shell from an already-evaluated stackpanel.devshell config.
# Unlike mkDevShell.nix which runs evalModules, this takes a pre-evaluated
# devshell configuration and builds a shell directly.
#
# Usage:
#   mkShellFromConfig { inherit pkgs; } {
#     devshellConfig = config.stackpanel.devshell;
#     stackpanelConfig = config.stackpanel;  # optional, for passthru
#     extraPackages = [ pkgs.jq ];
#   }
#
# The resulting shell includes:
#   - packages from devshellConfig.packages
#   - environment variable exports
#   - shell hooks (before, main, after phases)
#   - passthru with stackpanelConfig and stackpanelSerializable
# ==============================================================================
{ pkgs }:
{
  devshellConfig,
  stackpanelConfig ? null,
  extraPackages ? [ ],
}:
let
  lib = pkgs.lib;
  cfg = devshellConfig;

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

  # Pre-compute serialized packages
  devshellPackages = cfg.packages or [ ];
  commandPkgs = cfg._commandPkgs or [ ];
  allDevshellPackages = devshellPackages ++ commandPkgs;
  serializedDevshellPackages = map serializePackage allDevshellPackages;

  # User packages (already serialized in stackpanelConfig)
  userPackagesSerialized =
    if stackpanelConfig != null then
      let
        userPackagesCfg =
          stackpanelConfig.userPackages or {
            enable = false;
            serialized = [ ];
          };
      in
      if userPackagesCfg.enable or false then userPackagesCfg.serialized or [ ] else [ ]
    else
      [ ];

  # Combined serialized packages
  allSerializedPackages = serializedDevshellPackages ++ userPackagesSerialized;

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') (cfg.env or { })
  );

  shellHook = lib.concatStringsSep "\n\n" (
    lib.flatten [
      envExports
      (cfg.hooks.before or [ ])
      (cfg.hooks.main or [ ])
      (cfg.hooks.after or [ ])
    ]
  );
in
pkgs.mkShell {
  packages = (cfg.packages or [ ]) ++ (cfg._commandPkgs or [ ]) ++ extraPackages;
  nativeBuildInputs = cfg.nativeBuildInputs or [ ];
  buildInputs = cfg.buildInputs or [ ];
  shellHook = shellHook;

  passthru = {
    devshellConfig = cfg;
    # Full stackpanel config (may contain non-serializable values)
    inherit stackpanelConfig;
    # JSON-safe version for CLI/agent consumption
    stackpanelSerializable =
      if stackpanelConfig != null then serializeLib.filterSerializable stackpanelConfig else null;
    # Pre-serialized packages for fast access (avoids slow nix eval at runtime)
    stackpanelPackages = allSerializedPackages;
  };
}
