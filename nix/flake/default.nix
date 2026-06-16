# ==============================================================================
# default.nix - Stackpanel Flake Module
#
# The canonical flake-parts module for stackpanel. It auto-loads .stack config,
# evaluates stackpanel modules, creates devShells.default, and exposes derived
# packages, apps, checks, deployment outputs, and introspection data.
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
  flake-parts-lib,
  withSystem,
  ...
}:
let
  inherit (flake-parts-lib) mkPerSystemOption;

  serializeLib = import ../stackpanel/lib/serialize.nix { inherit lib; };

  hasProcessCompose = inputs ? process-compose-flake;
  hasGitHooks = inputs ? git-hooks;
  hasTreefmt = localInputs ? treefmt-nix;
  includeRootOutputs = config.stackpanel.includeRootOutputs or false;
  primarySystem = builtins.head config.systems;

  stackpanelOverlays = [
    localInputs.gomod2nix.overlays.default
    localInputs.bun2nix.overlays.default
    (
      final: _prev:
      let
        unstablePkgs = import localInputs.nixpkgs-unstable {
          inherit (final.stdenv.hostPlatform) system;
        };
      in
      {
        inherit (unstablePkgs) delve;
        inherit (unstablePkgs) gopls;
        inherit (unstablePkgs) gotools;
        inherit (unstablePkgs) gofumpt;
        inherit (unstablePkgs) golines;
      }
    )
  ];

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

  stackpanelImports = discoveredStackpanelImports ++ (config.stackpanel.imports or [ ]);

  baseNixosModules = {
    default = ../stackpanel/default.nix;
    aws = ../stackpanel/integrations/services/aws;
    network = ../stackpanel/network/network.nix;
    secrets = ../stackpanel/secrets/default.nix;
    theme = ../stackpanel/lib/theme.nix;
    caddy = ../stackpanel/integrations/services/caddy.nix;
    ci = ../stackpanel/apps/ci.nix;
    web-service = ../stackpanel/nixos/web-service.nix;
  };

  globalOutputs = import ./global-outputs.nix {
    inherit inputs self;
    inherit stackpanelImports;
  };

  deploymentTestSystem = "x86_64-linux";
  deploymentTestEnabled = includeRootOutputs && localInputs ? nixtest && localInputs ? namaka;
  deploymentTestInputs =
    let
      pkgs = import localInputs.nixpkgs {
        system = deploymentTestSystem;
        overlays = stackpanelOverlays;
      };
      options = localFlake.lib.getOptions { inherit pkgs; };
    in
    {
      topLevelOptionNames = builtins.attrNames options;
      deploymentOptionNames = builtins.attrNames options.deployment;
      deploymentAlchemyOptionNames = builtins.attrNames options.deployment.alchemy;
    };
  nixtestLib = lib.optionalAttrs deploymentTestEnabled (import "${localInputs.nixtest.outPath}/src");
in
{
  imports = [
    ../stackpanel/core/options
  ]
  ++ lib.optional hasProcessCompose inputs.process-compose-flake.flakeModule
  ++ lib.optional hasGitHooks inputs.git-hooks.flakeModule;

  options.stackpanel = {
    projectRoot = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "Project root path. Defaults to the flake source root.";
    };

    imports = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "Additional stackpanel module imports applied to global and per-system evaluations.";
    };

    includeRootOutputs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to expose Stackpanel's own package, formatter, and deployment test outputs.";
    };
  };

  options.perSystem = mkPerSystemOption (
    { lib, ... }:
    {
      options.stackpanel = {
        imports = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "Additional per-system stackpanel module imports.";
        };
      };
    }
  );

  config =
    let
      flakeLevelStackpanelConfig = config.stackpanel or { };
    in
    lib.mkMerge [
      {
        perSystem =
          {
            system,
            pkgs,
            lib,
            config,
            ...
          }:
          let
            perSystemStackpanelConfig = config.stackpanel or { };
            configLoader = import ./load-config.nix { inherit self inputs; };
            loadedConfig = configLoader.evalResolved {
              inherit lib pkgs;
              config = spConfig;
            };
            stackpanelConfigModule = configLoader.mkStackpanelModule { inherit lib pkgs; };
            effectiveRoot =
              if (flakeLevelStackpanelConfig.projectRoot or null) != null then
                flakeLevelStackpanelConfig.projectRoot
              else
                toString self;
            gitHooksConfig = loadedConfig.git-hooks or { };

            stackpanelEval = lib.evalModules {
              modules = [
                ../stackpanel
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
            devshellOutputs = spConfig.devshell;

            hooks =
              devshellOutputs.hooks or {
                before = [ ];
                main = [ ];
                after = [ ];
              };

            timingEnabled = (spConfig.debug or false) || (devshellOutputs.timing or false);
            wrapWithTimer =
              label: hookStr:
              if timingEnabled then
                ''
                  TIMEFORMAT=$'time ${label} completed in %3Rs'
                  time {
                  ${hookStr}
                  :
                  }
                ''
              else
                hookStr;
            timedHookList =
              phase: hooks':
              lib.imap0 (idx: hookStr: wrapWithTimer "hooks.${phase}[${toString idx}]" hookStr) (
                lib.filter (hookStr: hookStr != "") hooks'
              );

            stackpanelHook = lib.concatStringsSep "\n\n" (
              lib.flatten [
                (timedHookList "before" hooks.before)
                (timedHookList "main" hooks.main)
                (timedHookList "after" hooks.after)
              ]
            );

            allPackages = (devshellOutputs.packages or [ ]) ++ (devshellOutputs._commandPkgs or [ ]);
            profileEnabled = devshellOutputs.profile.enable or false;
            profileDrv = devshellOutputs.profile.package or null;
            shellPackages = if profileEnabled && profileDrv != null then [ profileDrv ] else allPackages;
            allEnv = devshellOutputs.env or { };

            shellHookContent = ''
              # ================================================================
              # Stackpanel Shell Hook (wrapper)
              # Generated by: nix/flake/default.nix
              # ================================================================

              __stackpanel_shell_hook_main() {
                if [[ -n "''${__STACKPANEL_HOOK_RAN:-}" ]]; then
                  return 0
                fi
                __STACKPANEL_HOOK_RAN=1

                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") allEnv
                )}

                ${stackpanelHook}
              }

              __stackpanel_shell_hook_main >&2
            '';

            shellHookFile = pkgs.writeTextFile {
              name = "stackpanel-shellhook";
              text = shellHookContent;
              executable = true;
              destination = "/shellhook.sh";
            };

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

            stackpanelShell = pkgs.mkShell {
              name = "stackpanel-${spConfig.name or "dev"}";

              packages = shellPackages;
              nativeBuildInputs = devshellOutputs.nativeBuildInputs or [ ];
              buildInputs = devshellOutputs.buildInputs or [ ];

              STACKPANEL_SHELL_HOOK_PATH = "${shellHookFile}/shellhook.sh";

              shellHook = ''
                source "${shellHookFile}/shellhook.sh"

                if [[ -n "''${STACKPANEL_STATE_DIR:-}" ]]; then
                  mkdir -p "$STACKPANEL_STATE_DIR"
                  ln -sf "${shellHookFile}/shellhook.sh" "$STACKPANEL_STATE_DIR/shellhook.sh"
                fi
              '';

              passthru = {
                stackpanelConfig = stackpanelSerializable;
                inherit stackpanelSerializable;
                stackpanelPackages = allSerializedPackages;
                devshellConfig = devshellOutputs;
                packages = allPackages;
                env = allEnv;
                processes = spConfig.process-compose.processes or { };
              };
            };

            rootPackages = import ./packages.nix { inherit pkgs; };
            treefmtEval = localInputs.treefmt-nix.lib.evalModule pkgs {
              projectRootFile = "flake.nix";
              programs = {
                nixfmt.enable = true;
                deadnix.enable = true;
                statix.enable = true;
                gofumpt.enable = true;
                goimports.enable = true;
                golines.enable = true;
                golines.maxLength = 88;
                golines.tabLength = 2;
              };
            };
          in
          lib.mkMerge [
            {
              _module.args.stackpanel = {
                inherit localFlake;
                packages = withSystem system ({ config, ... }: config.packages or { });
              };
            }

            (lib.mkIf (includeRootOutputs && hasTreefmt) {
              packages = lib.mapAttrs (_: lib.mkDefault) rootPackages;
              checks = {
                inherit (rootPackages) stackpanel;
                default-package = rootPackages.default;
                formatting = treefmtEval.config.build.check self;
              };
              formatter = treefmtEval.config.build.wrapper;
            })

            {
              legacyPackages = {
                stackpanelConfig = stackpanelSerializable;
                stackpanelFullConfig = spConfig;
                stackpanelPackages = allSerializedPackages;
                stackpanelOptions = stackpanelEval.options.stackpanel or { };
                stackpanelRawConfig = serializeLib.filterSerializable loadedConfig;
              };
            }

            (lib.mkIf (spConfig.enable or false) {
              devShells.default = lib.mkForce stackpanelShell;
            })

            (lib.mkIf (spConfig.enable or false) (
              let
                outputs = spConfig.outputs or { };
                directPkgs = lib.filterAttrs (_: v: lib.isDerivation v) outputs;
                nestedPkgs = lib.filterAttrs (_: v: builtins.isAttrs v && !(lib.isDerivation v)) outputs;
              in
              {
                packages = directPkgs;
                legacyPackages = nestedPkgs;
              }
            ))

            (lib.mkIf (spConfig.enable or false) (
              let
                containersComputed = spConfig.containersComputed or { };
                containerImages = containersComputed.images or { };
                copyScripts = containersComputed.copyScripts or { };
              in
              lib.mkIf (containerImages != { }) {
                packages = lib.mapAttrs' (name: image: {
                  name = "container-${name}";
                  value = image;
                }) containerImages;

                apps = lib.mapAttrs' (name: script: {
                  name = "copy-container-${name}";
                  value = {
                    type = "app";
                    program = "${script}";
                  };
                }) (lib.filterAttrs (_: v: v != null) copyScripts);
              }
            ))

            (lib.mkIf (spConfig.enable or false) (
              let
                simpleChecks = spConfig.checks or { };
                moduleChecks = spConfig.moduleChecksFlattened or { };
                allChecks = simpleChecks // moduleChecks;
              in
              lib.mkIf (allChecks != { }) {
                checks = allChecks;
              }
            ))

            (lib.mkIf (spConfig.enable or false) (
              let
                spApps = spConfig.flakeApps or { };
              in
              lib.mkIf (spApps != { }) {
                apps = spApps;
              }
            ))

            (lib.mkIf (hasGitHooks && (gitHooksConfig.enable or false)) {
              checks.pre-commit-check = inputs.git-hooks.lib.${system}.run {
                src = self;
                hooks = builtins.removeAttrs gitHooksConfig [ "enable" ];
              };
            })
          ];
      }

      (lib.mkIf hasProcessCompose {
        perSystem =
          { config, lib, ... }:
          let
            shell = config.devShells.default or null;
            processes = if shell != null then shell.passthru.processes or { } else { };
            hasProcesses = processes != { };
            sp = config.legacyPackages.stackpanelFullConfig or null;
            enabled = sp != null && (sp.enable or false) && hasProcesses;
          in
          lib.mkIf enabled {
            process-compose.dev.settings = {
              environment = sp.process-compose.environment or { };
              inherit processes;
            };
          };
      })

      {
        flake = {
          flakeInputs = builtins.removeAttrs inputs [ "self" ];
          nixosModules = baseNixosModules // globalOutputs.nixosModules;
          inherit (globalOutputs) nixosConfigurations colmenaHive;

          stackpanelConfig = withSystem primarySystem (
            { config, ... }: config.legacyPackages.stackpanelConfig or { }
          );

          stackpanelFullConfig = withSystem primarySystem (
            { config, ... }: config.legacyPackages.stackpanelFullConfig or { }
          );

          stackpanelRawConfig = withSystem primarySystem (
            { config, ... }: config.legacyPackages.stackpanelRawConfig or { }
          );

          stackpanelPackages = withSystem primarySystem (
            { config, ... }: config.legacyPackages.stackpanelPackages or [ ]
          );

          stackpanelOptions = withSystem primarySystem (
            { config, ... }: config.legacyPackages.stackpanelOptions or { }
          );
        }
        // lib.optionalAttrs deploymentTestEnabled {
          tests = {
            deployment = nixtestLib.assertTests (
              nixtestLib.runTests (import ../stackpanel/integrations/deployment/tests/unit deploymentTestInputs)
            );
          };

          deploymentSnapshots = localInputs.namaka.lib.load {
            src = ../stackpanel/integrations/deployment/tests/snapshots;
            inputs = deploymentTestInputs;
          };
        };
      }
    ];
}
