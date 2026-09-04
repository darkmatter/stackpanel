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

  discoveredStackpanelImports =
    if builtins.pathExists (self + "/.stack/modules") then
      [ (self + "/.stack/modules") ]
    else if builtins.pathExists (self + "/.stack/nix") then
      [ (self + "/.stack/nix") ]
    else if builtins.pathExists (self + "/.stackpanel/modules") then
      [ (self + "/.stackpanel/modules") ]
    else if builtins.pathExists (self + "/.stackpanel/nix") then
      [ (self + "/.stackpanel/nix") ]
    else
      [ ];

  # Flake-level adoption offers (templates/_addons) join module-contributed
  # offers under stackpanel.addons so `stack setup` sees one list.
  flakeAddonsModule = {
    stackpanel.addons = (import ./addons.nix { inherit lib; }).initAddons;
  };

  stackpanelImports =
    discoveredStackpanelImports ++ (config.stackpanel.imports or [ ]) ++ [ flakeAddonsModule ];

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
