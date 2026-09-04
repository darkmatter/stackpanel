# ==============================================================================
# per-system-outputs.nix - Stackpanel Per-System Flake Outputs
#
# A pure function that generates per-system flake outputs for a given system.
# Usage:
#   import ./per-system-outputs.nix { inherit pkgs inputs self system; }
#
# Returns:
#   { devShells, checks, apps, legacyPackages, packages }
#
# Architecture:
#   - Auto-loads config from .stackpanel/_internal.nix or .stackpanel/config.nix
#     via the shared load-config.nix helper.
#   - Uses lib.evalModules for internal stackpanel config (NixOS module system)
#   - Creates devShells.default via pkgs.mkShell with full passthru
#
# Global outputs (nixosConfigurations, colmenaHive, nixosModules) live in
# global-outputs.nix, which performs a lib-only evaluation without pkgs.
# ==============================================================================
{
  pkgs,
  inputs,
  self,
  system,
  # Optional: additional stackpanel module imports
  stackpanelImports ? [ ],
  # Optional: project root for pure eval (containers, fly deploy, etc.).
  # Defaults to `toString self` — the flake source as copied into the
  # Nix store, which is the canonical project root in pure eval.
  projectRoot ? toString self,
}:
let
  inherit (pkgs) lib;

  # Returns a list of all the entries in a folder

  # Serialization helpers for JSON-safe config
  serializeLib = import ../stackpanel/lib/serialize.nix { inherit lib; };

  # Check if user's flake has these optional inputs
  hasProcessCompose = inputs ? process-compose-flake;
  hasGitHooks = inputs ? git-hooks;

  # ===================================================================
  # Auto-load stackpanel config from .stackpanel/
  # Always use `self` for file discovery (works in pure evaluation)
  # ===================================================================
  configLoader = import ./load-config.nix { inherit self inputs; };

  stackpanelConfigModule = configLoader.mkStackpanelModule {
    inherit lib pkgs;
  };

  loadedConfig = configLoader.evalResolved {
    inherit lib pkgs;
    config = spConfig;
  };

  # Git hooks config (from stackpanel config)
  gitHooksConfig = loadedConfig.git-hooks or { };

  # ===================================================================
  # Evaluate stackpanel modules
  # ===================================================================
  # evalWith overlays extra modules on the same module set; used by the
  # speculative evaluation behind `stack setup` (see per-system/outputs.nix).
  evalWith =
    extraModules:
    lib.evalModules {
      modules = [
        ../stackpanel
        stackpanelConfigModule
      ]
      ++ lib.optional (projectRoot != null) {
        # Injected so containers + infra modules resolve files relative
        # to the user's working tree, not the read-only Nix store copy.
        stackpanel.root = projectRoot;
      }
      ++ stackpanelImports
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

  stackpanelSpeculate =
    {
      modules ? [ ],
      config ? { },
    }:
    let
      sp = (evalWith (modules ++ [ { stackpanel = config; } ])).config.stackpanel;
      writer = sp.files._writerDrv;
    in
    {
      files = sp.files._plan;
      doctor = sp.doctorList;
      addons = sp.addonsList;
      writerDrvPath = builtins.toString writer.drvPath;
      writerOutPath = builtins.toString writer;
      preflightManifestDrvPath = builtins.toString sp.files._preflightManifestDrv.drvPath;
      preflightManifestOutPath = builtins.toString sp.files._preflightManifestDrv;
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

  # When debug is enabled, wrap each hook entry with timing
  wrapWithTimer =
    label: hookStr:
    if spConfig.debug or spConfig.hooks.timing or false then
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

  # ===================================================================
  # Combine all packages
  # NOTE: process-compose's `dev` wrapper is provided by the devshell.
  # Enter with `nix develop`, then run `dev`.
  # ===================================================================
  allPackages = (devshellOutputs.packages or [ ]) ++ (devshellOutputs._commandPkgs or [ ]);

  # ===================================================================
  # Combine all env vars
  # ===================================================================
  allEnv = devshellOutputs.env or { };

  # ===================================================================
  # Build complete shellHook content
  # ===================================================================
  shellHookContent = ''
    # ================================================================
    # Stackpanel Shell Hook (wrapper)
    # Generated by: nix/flake/per-system-outputs.nix
    # ================================================================

    __stackpanel_shell_hook_main() {
      # Export environment variables
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") allEnv
      )}

      # Add language bin directories to PATH.
      if [[ -n "''${GOPATH:-}" ]]; then
        export PATH="$GOPATH/bin:$PATH"
      fi
      if [[ -n "''${CARGO_HOME:-}" ]]; then
        export PATH="$CARGO_HOME/bin:$PATH"
      fi

      # Stackpanel hooks (all output automatically goes to stderr)
      ${stackpanelHook}
    }

    # Run the hook with all output to stderr (so direnv doesn't capture/evaluate it)
    # Optionally tee to log file if state dir exists
    if [[ -d "''${STACKPANEL_STATE_DIR:-.stackpanel/state}" ]] 2>/dev/null; then
      CLICOLOR_FORCE=1 \
      FORCE_COLOR=3 \
      COLORTERM=truecolor \
      __stackpanel_shell_hook_main 2> \
          >(tee -a "''${STACKPANEL_STATE_DIR:-.stackpanel/state}/shell.log" >&2) \
        || status=$?
    else
      __stackpanel_shell_hook_main >&2 \
        || status=$?
    fi
    if [[ $status -ne 0 ]]; then
      echo "❌ Stackpanel shell hook exited with status $status" >&2
      exit $status
    fi
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
      inherit stackpanelSerializable;

      # Pre-serialized packages for fast access
      stackpanelPackages = allSerializedPackages;

      # Devshell outputs for introspection
      devshellConfig = devshellOutputs;

      # All packages in the shell
      packages = allPackages;

      # All env vars
      env = allEnv;

    };
  };

  # ===================================================================
  # Build outputs conditionally based on config
  # ===================================================================
  enabled = spConfig.enable or false;

  # Stackpanel outputs (packages from outputs option)
  spOutputs = spConfig.outputs or { };
  directPkgs = lib.filterAttrs (_: v: lib.isDerivation v) spOutputs;
  nestedPkgs = lib.filterAttrs (_: v: builtins.isAttrs v && !(lib.isDerivation v)) spOutputs;

  # Container outputs
  containersComputed = spConfig.containersComputed or { };
  containerImages = containersComputed.images or { };
  copyScripts = containersComputed.copyScripts or { };

  containerPackages = lib.mapAttrs' (name: image: {
    name = "container-${name}";
    value = image;
  }) containerImages;

  containerApps = lib.mapAttrs' (name: script: {
    name = "copy-container-${name}";
    value = {
      type = "app";
      program = "${script}";
    };
  }) (lib.filterAttrs (_: v: v != null) copyScripts);

  # Checks
  simpleChecks = spConfig.checks or { };
  moduleChecks = spConfig.moduleChecksFlattened or { };
  allChecks = simpleChecks // moduleChecks;

  # Git hooks check
  # Note: src must be a path (self), not a string (effectiveRoot)
  gitHooksCheck =
    if hasGitHooks && (gitHooksConfig.enable or false) then
      {
        pre-commit-check = inputs.git-hooks.lib.${system}.run {
          src = self;
          hooks = builtins.removeAttrs gitHooksConfig [ "enable" ];
        };
      }
    else
      { };

  # Flake apps
  spApps = spConfig.flakeApps or { };

  # Process-compose integration
  processes = stackpanelShell.passthru.processes or { };
  hasProcesses = processes != { };
  processComposeApp =
    if hasProcessCompose && enabled && hasProcesses then
      {
        # dev is the deafult command for developing on the respective repo.
        # The "golden path" of using stackpanel is:
        # ```
        #  $ nix develop
        #  $ dev
        # ```
        # This would start process-compose which starts all apps, services, etc.
        dev = {
          type = "app";
          program = "${pkgs.process-compose}/bin/process-compose";
        };
      }
    else
      { };
in
# Return the per-system flake outputs
{
  devShells = if enabled then { default = stackpanelShell; } else { };

  packages = if enabled then directPkgs // containerPackages else { };

  # Helpers for introspection - can be used to get LSP features for nixd and nil
  legacyPackages = {
    stackpanelConfig = stackpanelSerializable;
    stackpanelFullConfig = spConfig;
    stackpanelPackages = allSerializedPackages;
    stackpanelOptions = stackpanelEval.options.stackpanel or { };
    stackpanelRawConfig = serializeLib.filterSerializable loadedConfig;
    inherit stackpanelSpeculate;
  }
  // (if enabled then nestedPkgs else { });

  checks = if enabled then allChecks // gitHooksCheck else { };

  apps = if enabled then spApps // containerApps // processComposeApp else { };
}
