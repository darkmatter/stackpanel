# ==============================================================================
# default.nix - Stackpanel Flake Module
#
# THE single flake-parts module for stackpanel. This module:
#   1. Auto-loads config from .stackpanel/_internal.nix or .stackpanel/config.nix
#   2. Uses devenv.flakeModule for languages/services evaluation (when available)
#   3. Creates devShells.default via pkgs.mkShell with OUR passthru
#   4. Full control over passthru, shellHook ordering, packages
#
# Architecture:
#   - Devenv evaluates modules (languages.*, services.*, processes.*)
#   - We extract computed packages/env from devenv's evaluation
#   - We create the final shell with pkgs.mkShell for full control
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

  # Helper to serialize a package derivation to JSON-safe format
  serializePackage =
    pkg:
    if builtins.isAttrs pkg && pkg ? name then
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

  # Check if user's flake has these optional inputs
  hasDevenv = inputs ? devenv;
  hasProcessCompose = inputs ? process-compose-flake;
  hasGitHooks = inputs ? git-hooks;

  # Get devenv-tasks-fast-build from stackpanel's inputs
  stackpanelInputs = localFlake.inputs or { };
  hasStackpanelDevenv = stackpanelInputs ? devenv;
in
{
  # ===========================================================================
  # Imports - include devenv.flakeModule for proper evaluation
  # ===========================================================================
  imports = [
    # Stackpanel options (pkgs-free, safe for flake-parts top-level)
    ../stackpanel/core/options
  ]
  ++ lib.optional hasDevenv inputs.devenv.flakeModule
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

        devenvImports = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "Additional devenv module imports (for languages, services, etc.).";
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
      # Validation checks
      # -------------------------------------------------------------------------
      (
        let
          secretsEnabled = config.stackpanel.secrets.enable or false;
          hasAgenix = inputs ? agenix;
          check =
            if secretsEnabled && !hasAgenix then
              throw ''
                stackpanel.secrets.enable requires agenix.
                Add to your flake inputs:
                  agenix.url = "github:ryantm/agenix";
              ''
            else
              true;
        in
        lib.mkIf (secretsEnabled && check) { }
      )

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
            # ===================================================================
            internalConfigPath = projectRoot + "/.stackpanel/_internal.nix";
            simpleConfigPath = projectRoot + "/.stackpanel/config.nix";

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

            # ===================================================================
            # Devenv config path
            # ===================================================================
            devenvConfigPath = projectRoot + "/.stackpanel/devenv.nix";
            hasDevenvConfig = builtins.pathExists devenvConfigPath;

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
              specialArgs = { inherit pkgs lib inputs; };
            };

            spConfig = stackpanelEval.config.stackpanel;
            devshellOutputs = spConfig.devshell;

            # ===================================================================
            # Extract from devenv evaluation (if devenv.flakeModule is loaded)
            # The devenv.shells.default is configured below to import user's devenv.nix
            # This gives us properly evaluated languages.* config (GOPATH, GOROOT, etc.)
            #
            # IMPORTANT: We only extract `env` and `packages` from devenv.
            # We do NOT use devenv's `enterShell` because it contains devenv-specific
            # setup (PS1, DEVENV_STATE dirs, profile linking) that conflicts with ours.
            # ===================================================================
            devenvEval = config.devenv.shells.default or null;

            # Get packages from devenv (includes languages.* computed packages like delve, gopls)
            devenvPackages = if devenvEval != null then (devenvEval.packages or [ ]) else [ ];

            # Get env from devenv (includes computed values like GOPATH, GOROOT, GOTOOLCHAIN)
            # We extract this and merge it into our env, giving our values priority
            devenvEnv = if devenvEval != null then (devenvEval.env or { }) else { };

            # Get processes from devenv
            devenvProcesses = if devenvEval != null then (devenvEval.processes or { }) else { };

            # ===================================================================
            # Get devenv-tasks-fast-build
            # ===================================================================
            devenvTasksPkg =
              if hasStackpanelDevenv && stackpanelInputs.devenv ? packages.${system}.devenv-tasks-fast-build then
                [ stackpanelInputs.devenv.packages.${system}.devenv-tasks-fast-build ]
              else
                [ ];

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
            # NOTE: process-compose `dev` command is available via `nix run .#dev`
            # We don't add it to devshell packages to avoid infinite recursion
            # ===================================================================
            allPackages =
              (devshellOutputs.packages or [ ])
              ++ (devshellOutputs._commandPkgs or [ ])
              ++ devenvPackages
              ++ devenvTasksPkg;

            # ===================================================================
            # Combine all env vars
            # Filter out devenv's process-compose vars - we use our own process-compose.yaml
            # ===================================================================
            filteredDevenvEnv = builtins.removeAttrs devenvEnv [
              "PC_CONFIG_FILES"
              "PC_CONFIG"
              "PC_SOCKET_PATH"
              "PROCESS_COMPOSE_FILE"
              "PROCESS_COMPOSE_CONFIG"
            ];
            # Our env (devshellOutputs) takes priority over devenv's
            allEnv = filteredDevenvEnv // (devshellOutputs.env or { });

            # ===================================================================
            # Build complete shellHook content
            # ===================================================================
            shellHookContent = ''
              # ================================================================
              # Stackpanel Shell Hook
              # Generated by: nix/flake/default.nix
              # ================================================================

              # Export environment variables (includes GOPATH, GOROOT from devenv languages.*)
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") allEnv
              )}

              # Add language bin directories to PATH (replaces devenv's enterShell PATH modifications)
              # This handles languages.go ($GOPATH/bin), languages.rust ($CARGO_HOME/bin), etc.
              if [[ -n "''${GOPATH:-}" ]]; then
                export PATH="$GOPATH/bin:$PATH"
              fi
              if [[ -n "''${CARGO_HOME:-}" ]]; then
                export PATH="$CARGO_HOME/bin:$PATH"
              fi

              # Stackpanel hooks
              ${stackpanelHook}
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

            serializedPackages = map serializePackage allPackages;

            userPackagesCfg =
              spConfig.userPackages or {
                enable = false;
                serialized = [ ];
              };
            userPackagesSerialized =
              if userPackagesCfg.enable or false then userPackagesCfg.serialized or [ ] else [ ];

            allSerializedPackages = serializedPackages ++ userPackagesSerialized;

            # ===================================================================
            # Create OUR shell with pkgs.mkShell
            # ===================================================================
            stackpanelShell = pkgs.mkShell {
              name = "stackpanel-${spConfig.name or "dev"}";

              packages = allPackages;
              nativeBuildInputs = devshellOutputs.nativeBuildInputs or [ ];
              buildInputs = devshellOutputs.buildInputs or [ ];

              # Export path to shellHook file for inspection/debugging
              STACKPANEL_SHELL_HOOK_PATH = "${shellHookFile}/shellhook.sh";

              # Minimal shellHook that sources the full hook from the store
              # The full hook is at $STACKPANEL_SHELL_HOOK_PATH (also symlinked to .stackpanel/state/shellhook.sh)
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
                # Stackpanel config (serializable version for JSON/CLI access)
                # Full config is available via legacyPackages.stackpanelFullConfig
                stackpanelConfig = stackpanelSerializable;

                # JSON-safe serialized config for CLI/agent
                stackpanelSerializable = stackpanelSerializable;

                # Pre-serialized packages for fast access
                stackpanelPackages = allSerializedPackages;

                # Devshell outputs for introspection
                devshellConfig = devshellOutputs;

                # All packages in the shell
                packages = allPackages;

                # All env vars
                env = allEnv;

                # Process definitions (for process-compose integration)
                processes = devenvProcesses // (spConfig.process-compose.processes or { });

                # Devenv info
                devenv = {
                  evaluated = devenvEval != null;
                  packages = devenvPackages;
                  env = devenvEnv;
                  processes = devenvProcesses;
                  root = spConfig.root or null;
                };
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
                # Expose module options for introspection
                stackpanelOptions = stackpanelEval.options.stackpanel or { };
              };
            }

            # Always set devenv.root when devenv is available (required for pure evaluation)
            # This ensures `nix flake show` and FlakeHub publish work without --impure
            (lib.mkIf hasDevenv {
              devenv.shells.default = {
                # Set devenv.root for pure evaluation (required by devenv)
                # Uses effectiveRoot which comes from readStackpanelRoot module or falls back to self
                devenv.root = effectiveRoot;
              };
            })

            # Configure full devenv shell when stackpanel is enabled with devenv config
            # This imports the user's .stackpanel/devenv.nix so devenv properly evaluates
            # languages.* modules (e.g., languages.go sets GOPATH, GOROOT)
            (lib.mkIf (hasDevenv && hasDevenvConfig && (spConfig.enable or false)) (
              let
                # Detect which languages are used by stackpanel apps
                apps = spConfig.apps or { };
                hasGoApps = lib.any (app: app.go.enable or false) (lib.attrValues apps);
                # Add more language detection here as needed:
                # hasRustApps = lib.any (app: app.rust.enable or false) (lib.attrValues apps);
              in
              {
                devenv.shells.default = {
                  imports = [
                    # Import the devenv adapter to get stackpanel options in devenv
                    ../flake/modules/devenv.nix
                    # Import user's devenv.nix for languages, services, etc.
                    devenvConfigPath
                  ]
                  ++ (perSystemCfg.devenvImports or [ ]);

                  # Apply stackpanel config
                  stackpanel = loadedConfig;

                  # Auto-enable devenv languages based on stackpanel app configs
                  # This ensures GOPATH, GOROOT, etc. are set when Go apps are defined
                  languages.go.enable = lib.mkDefault hasGoApps;
                  # languages.rust.enable = lib.mkDefault hasRustApps;
                };
              }
            ))

            # Override devShells.default with OUR shell (has proper passthru)
            (lib.mkIf (spConfig.enable or false) {
              devShells.default = lib.mkForce stackpanelShell;
            })

            # Expose stackpanel.outputs as flake packages
            # Scripts are available via: nix run .#scripts.<script-name>
            (lib.mkIf (spConfig.enable or false) (
              let
                outputs = spConfig.outputs or { };
                # Separate derivations from nested attrsets
                directPkgs = lib.filterAttrs (_: v: lib.isDerivation v) outputs;
                nestedPkgs = lib.filterAttrs (_: v: builtins.isAttrs v && !(lib.isDerivation v)) outputs;
              in
              {
                # Direct packages go to packages.<name>
                packages = directPkgs;
                # Nested attrsets (like scripts) go to legacyPackages for nix run .#scripts.<name>
                legacyPackages = nestedPkgs;
              }
            ))

            # Expose stackpanel.checks and stackpanel.moduleChecksFlattened as flake checks
            # - stackpanel.checks: Simple checks (attrsOf package)
            # - stackpanel.moduleChecksFlattened: Structured module checks with categories
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

            # Expose stackpanel.flakeApps as flake apps (for nix run .#<name>)
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
      # NOTE: The `dev` command in devshell comes from our stackpanel module
      # This just provides a `nix run .#dev` option via process-compose-flake
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
          # Serializable stackpanel config (for CLI/agent access)
          stackpanelConfig = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelConfig or { }
          );

          # Full stackpanel config (may contain non-serializable values)
          stackpanelFullConfig = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelFullConfig or { }
          );

          # Pre-serialized packages for fast access
          stackpanelPackages = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelPackages or [ ]
          );

          # Module options for introspection (documentation, tooling)
          stackpanelOptions = withSystem "aarch64-darwin" (
            { config, ... }: config.legacyPackages.stackpanelOptions or { }
          );
        };
      }
    ];
}
