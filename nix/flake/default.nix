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
#   - Auto-loads config from .stack/config.nix or .stackpanel/config.nix (prefers .stack)
#   - Merge: config.nix + imports + data/github-collaborators.nix + config.local.nix
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
  # Config directory: .stack (preferred) with .stackpanel fallback
  # Always use `self` for file discovery (works in pure evaluation)
  # ===================================================================
  hasStackConfig = builtins.pathExists (self + "/.stack/config.nix");
  hasStackpanelConfig = builtins.pathExists (self + "/.stackpanel/config.nix");
  configDir =
    if hasStackConfig then
      ".stack"
    else if hasStackpanelConfig then
      ".stackpanel"
    else
      ".stack";

  configDirPath = self + "/${configDir}";
  simpleConfigPath = configDirPath + "/config.nix";

  hasSimpleConfig = builtins.pathExists simpleConfigPath;

  loadConfig =
    path:
    let
      raw = import path;
      result =
        if builtins.isFunction raw then
          raw {
            inherit
              pkgs
              lib
              inputs
              self
              ;
            config = result;
          }
        else
          raw;
    in
    result;

  # In-flake merge: replaces _internal.nix when it's absent (preferred for .stack)
  # Merge order: config.nix + imports → + data/github-collaborators.nix → + config.local.nix
  stackpanelRootFromMarker =
    let
      markerPath = self + "/.stackpanel-root";
    in
    if builtins.pathExists markerPath then
      let
        content = lib.removeSuffix "\n" (builtins.readFile markerPath);
      in
      if content != "" && content != "." then content else null
    else
      null;

  localConfigPath =
    if stackpanelRootFromMarker != null then
      stackpanelRootFromMarker + "/${configDir}/config.local.nix"
    else
      null;
  hasLocalConfig = localConfigPath != null && builtins.pathExists localConfigPath;
  rawLocalConfig = if hasLocalConfig then import localConfigPath else { };
  localConfig =
    let
      result =
        if builtins.isFunction rawLocalConfig then
          rawLocalConfig {
            inherit
              pkgs
              lib
              inputs
              self
              ;
            config = result;
          }
        else
          rawLocalConfig;
    in
    result;

  processImports =
    config:
    let
      imports = config.imports or [ ];
      configWithoutImports = builtins.removeAttrs config [ "imports" ];
      importModule =
        path:
        let
          imported = import path;
          result =
            if builtins.isFunction imported then
              imported {
                inherit
                  pkgs
                  lib
                  inputs
                  self
                  ;
                config = result;
              }
            else
              imported;
        in
        processImports result;
      importedConfigs = map importModule imports;
    in
    lib.foldl lib.recursiveUpdate { } (importedConfigs ++ [ configWithoutImports ]);

  ghCollabsPath = configDirPath + "/data/github-collaborators.nix";
  ghCollabs =
    if builtins.pathExists ghCollabsPath then import ghCollabsPath else { collaborators = { }; };

  toUser = name: collab: {
    inherit name;
    github = collab.login or name;
    public-keys = collab.publicKeys or [ ];
    secrets-allowed-environments =
      if collab.isAdmin or false then
        [
          "dev"
          "staging"
          "production"
        ]
      else
        [ "dev" ];
  };
  github-team = lib.mapAttrs (name: user: toUser name user) ghCollabs.collaborators;

  loadedConfig =
    if hasSimpleConfig then
      let
        baseUserConfig = loadConfig simpleConfigPath;
        userConfig = processImports baseUserConfig;
        configWithUsers = userConfig // {
          users = lib.recursiveUpdate github-team (userConfig.users or { });
        };
      in
      lib.recursiveUpdate configWithUsers localConfig
    else
      { };

  # Git hooks config (from stackpanel config)
  gitHooksConfig = loadedConfig.git-hooks or { };

  stackpanelConfigModule = {
    stackpanel = loadedConfig;
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

  devenvConfigPath = configDirPath + "/devenv.nix";
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
        # Provide explicit CLI version for newer devenv modules that compare
        # process manager defaults against devenv CLI major versions.
        devenv.cli.version = "2.0";
        devenv.cliVersion = "2.0";
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

  # Extract devenv config if available (only when both devenv input and config file exist)
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
  # Unified profile: single buildEnv instead of 90+ PATH entries
  #
  # When the profile module is enabled, we pass the profile derivation
  # (plus any devenv packages that aren't part of our module system) to
  # mkShell instead of the full individual package list.  This collapses
  # PATH down to one or two entries.
  #
  # allPackages is still kept around for serialization / passthru.
  # ===================================================================
  profileEnabled = devshellOutputs.profile.enable or false;
  profileDrv = devshellOutputs.profile.package or null;

  shellPackages =
    if profileEnabled && profileDrv != null then [ profileDrv ] ++ devenvPackages else allPackages;

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
  allEnv = builtins.removeAttrs (filteredDevenvEnv // (devshellOutputs.env or { })) [
    "name"
    "packages"
    "nativeBuildInputs"
    "buildInputs"
    "shellHook"
    "passthru"
  ];

  # ===================================================================
  # Build complete shellHook content
  # ===================================================================
  shellHookContent = ''
    # syntax: bash
    # ================================================================
    # Stackpanel Shell Hook (wrapper)
    # Generated by: nix/flake/default.nix
    # ================================================================

    __stackpanel_shell_hook_main() {
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
    # Optionally tee to log file if profile dir exists
    if [[ -d "''${STACKPANEL_STATE_DIR:-.stack/profile}" ]] 2>/dev/null; then
      CLICOLOR_FORCE=1 \
      FORCE_COLOR=3 \
      COLORTERM=truecolor \
      __stackpanel_shell_hook_main 2> \
          >(tee -a "''${STACKPANEL_STATE_DIR:-.stack/profile}/shell.log" >&2) \
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
  stackpanelShell = pkgs.mkShell (
    # Pass allEnv as direct mkShell attributes so they appear as top-level
    # exports in `nix print-dev-env`. This is what lets the Go agent (and
    # anything else that doesn't run shellHook) see SOPS_AGE_KEY_CMD,
    # GOPATH, STACKPANEL_* vars, etc.
    allEnv
    // {
      name = "stackpanel-${spConfig.name or "dev"}";

      packages = shellPackages;
      nativeBuildInputs = devshellOutputs.nativeBuildInputs or [ ];
      buildInputs = devshellOutputs.buildInputs or [ ];

      # Export path to shellHook file for inspection/debugging
      STACKPANEL_SHELL_HOOK_PATH = "${shellHookFile}/shellhook.sh";

      # Avoid running devenv tasks
      DEVENV_SKIP_TASKS = "1";

      # Minimal shellHook that sources the full hook from the store
      # The full hook is at $STACKPANEL_SHELL_HOOK_PATH (also symlinked to .stack/profile/shellhook.sh)
      shellHook = ''
        # Source the full shellHook from the Nix store
        source "${shellHookFile}/shellhook.sh"

        # Symlink to profile dir for easy inspection (after STACKPANEL_STATE_DIR is set)
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
    }
  );

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
