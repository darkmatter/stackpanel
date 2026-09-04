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

  # evalWith overlays extra modules on the exact module set the shell uses.
  # `stack setup` calls it (via legacyPackages.stackpanelSpeculate) to preview
  # what accepting an addon would generate: pure, nothing is written or built.
  evalWith =
    extraModules:
    lib.evalModules {
      modules = [
        ../../stackpanel
        stackpanelConfigModule
        {
          stackpanel.root = lib.mkDefault effectiveRoot;
        }
      ]
      ++ stackpanelImports
      ++ (perSystemStackpanelConfig.imports or [ ])
      ++ extraModules;
      specialArgs = {
        inherit
          pkgs
          lib
          inputs
          self
          ;
      };
    };

  stackpanelEval = evalWith [ ];

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
    evalWith
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
