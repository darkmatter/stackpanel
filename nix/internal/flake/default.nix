# ==============================================================================
# default.nix - Stackpanel Flake Module
#
# THE single flake-parts module for stackpanel. This module:
#   1. Auto-loads config from .stackpanel/_internal.nix or .stackpanel/config.nix
#   2. Evaluates stackpanel modules via lib.evalModules
#   3. Creates devShells.default via pkgs.mkShell with full passthru
#   4. Full control over passthru, shellHook ordering, packages
#
# Usage:
#   imports = [ inputs.stackpanel.flakeModules.default ];
# ==============================================================================
{
  localFlake,
  withSystem,
}:
{
  lib,
  self,
  inputs,
  config,
  flake-parts-lib,
  ...
}:
let
  inherit (flake-parts-lib) mkPerSystemOption;

  # Serialization helpers for JSON-safe config
  serializeLib = import ../stackpanel/lib/serialize.nix { inherit lib; };

  # Check if user's flake has these optional inputs
  hasProcessCompose = inputs ? process-compose-flake;
  hasGitHooks = inputs ? git-hooks;
in
{
  # ===========================================================================
  # Imports
  # ===========================================================================
  imports = [
    # Stackpanel options (pkgs-free, safe for flake-parts top-level)
    ../stackpanel/core/options
  ]
  ++ lib.optional hasProcessCompose inputs.process-compose-flake.flakeModule
  ++ lib.optional hasGitHooks inputs.git-hooks.flakeModule;

  # ===========================================================================
  # Flake-level options
  # ===========================================================================
  options.stackpanel = {
    projectRoot = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "Project root path (string or path). Defaults to self (flake root).";
    };
  };

  # ===========================================================================
  # perSystem options
  # ===========================================================================
  options.perSystem = mkPerSystemOption (
    { lib, ... }:
    {
      options.stackpanel = {
        imports = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "Additional stackpanel module imports.";
        };
      };
    }
  );

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config =
    let
      # Capture flake-level stackpanel config in the enclosing scope
      # This makes it available to perSystem without needing _module.args
      flakeLevelStackpanelConfig = config.stackpanel or { };
    in
    lib.mkMerge [
      # -------------------------------------------------------------------------
      # perSystem configuration
      # -------------------------------------------------------------------------
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
            # Top-level flake config (captured from enclosing scope)
            flakeCfg = flakeLevelStackpanelConfig;

            # perSystem stackpanel config
            perSystemCfg = config.stackpanel or { };

            # Project root for loading config files
            projectRoot = flakeCfg.projectRoot or self;

            # ===================================================================
            # Auto-load stackpanel config from .stackpanel/
            # Always use `self` for file discovery (works in pure evaluation)
            # ===================================================================
            internalConfigPath = self + "/.stackpanel/_internal.nix";
            simpleConfigPath = self + "/.stackpanel/config.nix";

            hasInternalConfig = builtins.pathExists internalConfigPath;
            hasSimpleConfig = builtins.pathExists simpleConfigPath;

            loadConfig =
              path:
              let
                raw = import path;
              in
              if builtins.isFunction raw then raw { inherit pkgs lib; } else raw;

            loadedConfig =
              if hasInternalConfig then
                loadConfig internalConfigPath
              else if hasSimpleConfig then
                loadConfig simpleConfigPath
              else
                { };

            # Compute the effective root - prefer flake-level projectRoot, fallback to self
            effectiveRoot =
              let
                flakeRoot = flakeCfg.projectRoot or null;
              in
              if flakeRoot != null then flakeRoot else toString self;

            stackpanelConfigModule = {
              stackpanel = loadedConfig // {
                # Set root from flake-level projectRoot (set by readStackpanelRoot module)
                root = lib.mkDefault effectiveRoot;
              };
            };

            # Git hooks config (from stackpanel config)
            gitHooksConfig = loadedConfig.git-hooks or { };

            # ===================================================================
            # Evaluate stackpanel modules
            # ===================================================================
            stackpanelEval = lib.evalModules {
              modules = [
                ../stackpanel
                stackpanelConfigModule
              ]
              ++ (perSystemCfg.imports or [ ]);
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

            # ===================================================================
            # Build shell hook from stackpanel hooks
            # ===================================================================
            hooks =
              devshellOutputs.hooks or {
                before = [ ];
                main = [ ];
                after = [ ];
              };

            stackpanelHook = lib.concatStringsSep "\n\n" (
              lib.flatten [
                hooks.before
                hooks.main
                hooks.after
              ]
            );

            # ===================================================================
            # Combine all packages
            # ===================================================================
            allPackages = (devshellOutputs.packages or [ ]) ++ (devshellOutputs._commandPkgs or [ ]);

            # ===================================================================
            # Unified profile: single buildEnv instead of 90+ PATH entries
            #
            # When the profile module is enabled, we pass the profile derivation
            # to mkShell instead of the full individual package list.  This
            # collapses PATH down to a single entry.
            #
            # allPackages is still kept around for serialization / passthru.
            # ===================================================================
            profileEnabled = devshellOutputs.profile.enable or false;
            profileDrv = devshellOutputs.profile.package or null;

            shellPackages =
              if profileEnabled && profileDrv != null then
                [ profileDrv ]
              else
                allPackages;

            # ===================================================================
            # All env vars (from stackpanel modules only)
            # ===================================================================
            allEnv = devshellOutputs.env or { };

            # ===================================================================
            # Build complete shellHook content
            # ===================================================================
            shellHookContent = ''
              # ================================================================
              # Stackpanel Shell Hook (wrapper)
              # Generated by: nix/flake/default.nix
              # ================================================================

              __stackpanel_shell_hook_main() {
                # Prevent the hook from running twice in the same shell
                if [[ -n "''${__STACKPANEL_HOOK_RAN:-}" ]]; then
                  return 0
                fi
                __STACKPANEL_HOOK_RAN=1

                # Export environment variables
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") allEnv
                )}

                # Stackpanel hooks (includes language toolchain setup from
                # stackpanel.languages.* modules: GOPATH/bin, node_modules/.bin, etc.)
                ${stackpanelHook}
              }

              # Run the hook in the CURRENT shell so exports and eval statements
              # (like starship init) persist. We must NOT use a pipe here because
              # pipes run the left-hand side in a subshell, losing all side effects.
              # Output goes to stderr so direnv doesn't capture it.
              __stackpanel_shell_hook_main >&2
            '';

            # Write shellHook to a file in the Nix store
            shellHookFile = pkgs.writeTextFile {
              name = "stackpanel-shellhook";
              text = shellHookContent;
              executable = true;
              destination = "/shellhook.sh";
            };

            # ===================================================================
            # JSON-safe serialized config
            # ===================================================================
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

            # ===================================================================
            # Create shell with pkgs.mkShell
            # ===================================================================
            stackpanelShell = pkgs.mkShell {
              name = "stackpanel-${spConfig.name or "dev"}";

              packages = shellPackages;
              nativeBuildInputs = devshellOutputs.nativeBuildInputs or [ ];
              buildInputs = devshellOutputs.buildInputs or [ ];

              # Export path to shellHook file for inspection/debugging
              STACKPANEL_SHELL_HOOK_PATH = "${shellHookFile}/shellhook.sh";

              # Minimal shellHook that sources the full hook from the store
              shellHook = ''
                # Source the full shellHook from the Nix store
                source "${shellHookFile}/shellhook.sh"

                # Symlink to state dir for easy inspection (after STACKPANEL_STATE_DIR is set)
                if [[ -n "''${STACKPANEL_STATE_DIR:-}" ]]; then
                  mkdir -p "$STACKPANEL_STATE_DIR"
                  ln -sf "${shellHookFile}/shellhook.sh" "$STACKPANEL_STATE_DIR/shellhook.sh"
                fi
              '';

              # FULL CONTROL over passthru
              passthru = {
                stackpanelConfig = stackpanelSerializable;
                stackpanelSerializable = stackpanelSerializable;
                stackpanelPackages = allSerializedPackages;
                devshellConfig = devshellOutputs;
                packages = allPackages;
                env = allEnv;
                processes = spConfig.process-compose.processes or { };
              };
            };

          in
          lib.mkMerge [
            # Make stackpanel helpers available
            {
              _module.args.stackpanel = {
                inherit localFlake;
                packages = withSystem system ({ config, ... }: config.packages or { });
              };
            }

            # Expose config via legacyPackages
            {
              legacyPackages = {
                stackpanelConfig = stackpanelSerializable;
                stackpanelFullConfig = spConfig;
                stackpanelPackages = allSerializedPackages;
                stackpanelOptions = stackpanelEval.options.stackpanel or { };
                stackpanelRawConfig = serializeLib.filterSerializable loadedConfig;
              };
            }

            # Set devShells.default
            (lib.mkIf (spConfig.enable or false) {
              devShells.default = lib.mkForce stackpanelShell;
            })

            # Expose stackpanel.outputs as flake packages
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

            # Expose container images and copy scripts as flake outputs
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
                }) copyScripts;
              }
            ))

            # Expose checks
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

            # Expose flakeApps
            (lib.mkIf (spConfig.enable or false) (
              let
                spApps = spConfig.flakeApps or { };
              in
              lib.mkIf (spApps != { }) {
                apps = spApps;
              }
            ))

            # Git hooks check
            (lib.mkIf (hasGitHooks && (gitHooksConfig.enable or false)) {
              checks.pre-commit-check = inputs.git-hooks.lib.${system}.run {
                src = projectRoot;
                hooks = builtins.removeAttrs gitHooksConfig [ "enable" ];
              };
            })
          ];
      }

      # -------------------------------------------------------------------------
      # Process-compose integration (for nix run .#dev)
      # -------------------------------------------------------------------------
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
              processes = processes;
            };
          };
      })

      # -------------------------------------------------------------------------
      # Flake-level outputs
      # -------------------------------------------------------------------------
      {
        flake = {
          stackpanelConfig = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelConfig or { }
          );

          stackpanelFullConfig = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelFullConfig or { }
          );

          stackpanelRawConfig = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelRawConfig or { }
          );

          stackpanelPackages = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelPackages or [ ]
          );

          stackpanelOptions = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelOptions or { }
          );
        };
      }
    ];
}
