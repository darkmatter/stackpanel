# ==============================================================================
# default.nix - Stackpanel Flake Outputs Generator
#
# A pure function that generates flake outputs for a given system.
# This replaces the previous flake-parts module with explicit function calls.
# Usage:
#   import ./default.nix { inherit pkgs inputs self system; }
#
# Returns:
#   { devShells, checks, apps, legacyPackages, packages }
#
# Architecture:
#   - Auto-loads config from .stackpanel/_internal.nix or .stackpanel/config.nix
#   - Uses lib.evalModules for internal stackpanel config (NixOS module system)
#   - Creates devShells.default via pkgs.mkShell with full passthru
#   - Optionally integrates devenv for languages/services if available
# ==============================================================================
{
  pkgs,
  inputs,
  self,
  system,
  # Optional: override the project root (defaults to self)
  projectRoot ? null,
  # Optional: additional stackpanel module imports
  stackpanelImports ? [ ],
}:
let
  lib = pkgs.lib;

  # Returns a list of all the entries in a folder
  listEntries = path: map (name: path + "/${name}") (builtins.attrNames (builtins.readDir path));

  # Serialization helpers for JSON-safe config
  serializeLib = import ../stackpanel/lib/serialize.nix { inherit lib; };

  # Check if user's flake has these optional inputs
  hasDevenv = inputs ? devenv;
  hasProcessCompose = inputs ? process-compose-flake;
  hasGitHooks = inputs ? git-hooks;

  # ===================================================================
  # Compute effective project root
  # ===================================================================
  effectiveRoot = if projectRoot != null then projectRoot else toString self;

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

  # Git hooks config (from stackpanel config)
  gitHooksConfig = loadedConfig.git-hooks or { };

  stackpanelConfigModule = {
    stackpanel = loadedConfig // {
      # Set root from projectRoot
      root = lib.mkDefault effectiveRoot;
    };
  };

  # ===================================================================
  # Evaluate stackpanel modules
  # ===================================================================
  stackpanelEval = lib.evalModules {
    modules = [
      ../stackpanel
      stackpanelConfigModule
    ]
    ++ stackpanelImports;
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
  # Extract from devenv evaluation (if provided)
  # This gives us properly evaluated languages.* config (GOPATH, GOROOT, etc.)
  #
  # IMPORTANT: We only extract `env` and `packages` from devenv.
  # We do NOT use devenv's `enterShell` because it contains devenv-specific
  # setup (PS1, DEVENV_STATE dirs, profile linking) that conflicts with ours.
  # ===================================================================

  devenvConfigPath = self + "/.stackpanel/devenv.nix";
  hasDevenvConfig = builtins.pathExists devenvConfigPath;

  devenvModule =
    args:
    let
      devenv-toplevel = import (inputs.devenv.modules + /top-level.nix) args;
    in
    {
      options = devenv-toplevel.options;
      # Here we could also pick and match and not use all of devenv's
      # imports, but only the parts that we find useful.
      imports = devenv-toplevel.imports;
      config = lib.recursiveUpdate devenv-toplevel.config ({
        # Set devenv.root for pure evaluation (required by devenv)
        # Uses effectiveRoot which comes from readStackpanelRoot module or falls back to self
        devenv.root = effectiveRoot;
        # Fails checking cliVersion otherwise
        devenv.warnOnNewVersion = false;
        # cliVersion = inputs.devenv.version;
        # Ignore devenv's enterShell. We need the enterShell of the
        # other submodules, but the top level one adds things that
        # conflict with our shellHook (like PS1 modifications,
        # DEVENV_STATE_DIR setup, profile linking, etc.)
        enterShell = "";
      });
    };

  devenvEval = lib.evalModules {
    modules = [
      devenvModule
      devenvConfigPath
    ];
    specialArgs = {
      inherit pkgs inputs;
      self = inputs.devenv;
    };
  };

  # Extract devenv config if available
  devenvConfig = if hasDevenv && hasDevenvConfig then devenvEval.config else null;

  # Get packages from devenv (includes languages.* computed packages like delve, gopls)
  devenvPackages = if devenvConfig != null then (devenvConfig.packages or [ ]) else [ ];

  # Get env from devenv (includes computed values like GOPATH, GOROOT, GOTOOLCHAIN)
  # We extract this and merge it into our env, giving our values priority
  devenvEnv = if devenvConfig != null then (devenvConfig.env or { }) else { };

  # Get processes from devenv
  devenvProcesses = if devenvConfig != null then (devenvConfig.processes or { }) else { };

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
      (lib.optionals (devenvConfig != null) [
        "echo \"⚙️  Entering devenv shell...\""
        devenvConfig.enterShell
      ])
      hooks.after
    ]
  );

  # ===================================================================
  # Combine all packages
  # NOTE: process-compose `dev` command is available via `nix run .#dev`
  # We don't add it to devshell packages to avoid infinite recursion
  # ===================================================================
  allPackages =
    (devshellOutputs.packages or [ ]) ++ (devshellOutputs._commandPkgs or [ ]) ++ devenvPackages;

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
    # Stackpanel Shell Hook (wrapper)
    # Generated by: nix/flake/default.nix
    # ================================================================

    __stackpanel_shell_hook_main() {
      # Prevent recursive entry
      if [[ -n "''${__STACKPANEL_SHELL_ACTIVE:-}" ]]; then
        echo "⚠️  Already in stackpanel shell - preventing recursive entry"
        return 0
      fi
      export __STACKPANEL_SHELL_ACTIVE=1

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

    # Avoid running devenv tasks
    DEVENV_SKIP_TASKS = "1";

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
        evaluated = devenvConfig != null;
        packages = devenvPackages;
        env = devenvEnv;
        processes = devenvProcesses;
        root = spConfig.root or null;
      };
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
      let
        pcSettings = {
          environment = spConfig.process-compose.environment or { };
          processes = processes;
        };
        # Create a simple process-compose wrapper
        pcConfig = pkgs.writeText "process-compose.json" (builtins.toJSON pcSettings);
      in
      {
        dev = {
          type = "app";
          program = "${pkgs.process-compose}/bin/process-compose";
        };
      }
    else
      { };

in
# Return the flake outputs for this system
{
  devShells = if enabled then { default = stackpanelShell; } else { };

  packages = if enabled then directPkgs // containerPackages else { };

  legacyPackages = {
    stackpanelConfig = stackpanelSerializable;
    stackpanelFullConfig = spConfig;
    stackpanelPackages = allSerializedPackages;
    stackpanelOptions = stackpanelEval.options.stackpanel or { };
    stackpanelRawConfig = serializeLib.filterSerializable loadedConfig;
  }
  // (if enabled then nestedPkgs else { });

  checks = if enabled then allChecks // gitHooksCheck else { };

  apps = if enabled then spApps // containerApps // processComposeApp else { };
}
