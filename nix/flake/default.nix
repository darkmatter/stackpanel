# ==============================================================================
# default.nix - Stackpanel Flake Module (composer)
#
# Thin flake-parts entrypoint: loads options, overlays, the integration
# registry, evaluates stackpanel per-system, and merges flake outputs.
# External flakes register under ./integrations/ — see integrations/README.md.
# ==============================================================================
{
  localFlake,
  localInputs,
}:
{
  lib,
  self,
  inputs,
  config,
  withSystem,
  ...
}:
let
  stackpanelOverlays = import ./overlays.nix { inherit localInputs; };

  includeRootOutputs = config.stackpanel.includeRootOutputs or false;
  primarySystem = builtins.head config.systems;

  stackpanelImports = import ./stackpanel-imports.nix {
    inherit lib self;
    extraImports = config.stackpanel.imports or [ ];
  };

  registry = import ./integrations {
    inherit
      localFlake
      localInputs
      inputs
      lib
      ;
  };

  flakeLevelStackpanelConfig = config.stackpanel or { };
in
{
  imports = [
    ./options.nix
    ../stackpanel/core/options
  ]
  ++ registry.flakeModules;

  config = lib.mkMerge (
    [
      {
        perSystem =
          args@{
            system,
            pkgs,
            lib,
            config,
            ...
          }:
          let
            perSystemStackpanelConfig = config.stackpanel or { };

            eval = import ./per-system/eval.nix {
              inherit
                lib
                pkgs
                self
                inputs
                localFlake
                stackpanelImports
                flakeLevelStackpanelConfig
                perSystemStackpanelConfig
                ;
            };

            integrationCtx = args // {
              inherit
                self
                inputs
                localFlake
                localInputs
                includeRootOutputs
                eval
                ;
              inherit (eval) spConfig loadedConfig;
            };

            shell = import ./per-system/shell.nix {
              inherit pkgs lib eval;
              extraPackages = registry.extraShellPackages integrationCtx;
            };
          in
          lib.mkMerge [
            (import ./per-system/outputs.nix {
              inherit
                lib
                eval
                shell
                localFlake
                withSystem
                system
                ;
            })
            (registry.mkPerSystem integrationCtx)
          ];
      }

      (import ./flake-outputs.nix {
        inherit
          lib
          inputs
          self
          localFlake
          localInputs
          withSystem
          stackpanelOverlays
          stackpanelImports
          includeRootOutputs
          primarySystem
          ;
      })
    ]
    ++ map (
      fc:
      fc {
        inherit
          lib
          config
          inputs
          self
          ;
      }
    ) registry.flakeConfigs
  );
}
