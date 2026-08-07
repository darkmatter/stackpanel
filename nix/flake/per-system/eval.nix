# ==============================================================================
# per-system/eval.nix — Load .stack config and evaluate stackpanel modules
#
# Returns an attrset used by shell.nix, outputs.nix, and flake integrations.
# ==============================================================================
{
  lib,
  pkgs,
  self,
  inputs,
  stackpanelImports,
  flakeLevelStackpanelConfig,
  perSystemStackpanelConfig,
}:
let
  serializeLib = import ../../stackpanel/lib/serialize.nix { inherit lib; };

  configLoader = import ../load-config.nix { inherit self inputs; };
  stackpanelConfigModule = configLoader.mkStackpanelModule { inherit lib pkgs; };

  effectiveRoot =
    if (flakeLevelStackpanelConfig.projectRoot or null) != null then
      flakeLevelStackpanelConfig.projectRoot
    else
      toString self;

  stackpanelEval = lib.evalModules {
    modules = [
      ../../stackpanel
      stackpanelConfigModule
      {
        stackpanel.root = lib.mkDefault effectiveRoot;
      }
    ]
    ++ stackpanelImports
    ++ (perSystemStackpanelConfig.imports or [ ]);
    specialArgs = {
      inherit
        pkgs
        lib
        inputs
        self
        ;
    };
  };

  spConfig = stackpanelEval.config.stackpanel;

  loadedConfig = configLoader.evalResolved {
    inherit lib pkgs;
    config = spConfig;
  };

  allPackages = (spConfig.devshell.packages or [ ]) ++ (spConfig.devshell._commandPkgs or [ ]);

  stackpanelSerializable = serializeLib.filterSerializable spConfig;
  serializedPackages = map serializeLib.serializePackage allPackages;
  userPackagesCfg =
    spConfig.userPackages or {
      enable = false;
      serialized = [ ];
    };
  userPackagesSerialized =
    if userPackagesCfg.enable or false then userPackagesCfg.serialized or [ ] else [ ];
  allSerializedPackages = serializedPackages ++ userPackagesSerialized;
in
{
  inherit
    stackpanelEval
    spConfig
    loadedConfig
    effectiveRoot
    allPackages
    stackpanelSerializable
    allSerializedPackages
    serializeLib
    ;
}
