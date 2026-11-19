# ==============================================================================
# cli.nix
#
# CLI-based file generation for stackpanel.
#
# This module aggregates configuration from various Stackpanel options and
# invokes the `stack hook` CLI command when entering the devshell.
# All codegen is kicked off as a result of this invocation.
#
# Generated files (by CLI):
#   - .stack/state/stackpanel.json (runtime state)
#   - .stack/gen/ide/vscode/* (VS Code workspace, loader script)
#
# The configuration is serialized to JSON and passed to the CLI, which handles
# the actual file generation. This keeps Nix pure while delegating imperative
# file operations to the Go CLI.
#
# Enable with: stackpanel.cli.enable = true (default)
# ==============================================================================
{
  lib,
  config,
  pkgs,
  inputs ? { },
  localFlake ? null,
  self ? { },
  ...
}:
let
  cfg = config.stackpanel;
  portsCfg =
    config.stackpanel.ports or {
      project-name = "unknown";
      base-port = 5000;
    };
  ideCfg =
    config.stackpanel.ide or {
      enable = false;
      vscode = {
        enable = false;
        workspace-name = "workspace";
      };
    };
  pcCfg =
    cfg.process-compose or {
      port = null;
    };
  serialize = import ../lib/serialize.nix { inherit lib; };
  publicState = serialize.projectState cfg;
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs =
    cfg.dirs or {
      home = ".stack";
      state = ".stack/profile";
      profile = ".stack/profile";
      keys = ".stack/keys";
      gen = ".stack/gen";
      config = ./.;
    };

  # Stamp stack --version with the Stackpanel flake revision when available.
  # localFlake is the Stackpanel source flake (not the consumer repo).
  sourceFlake = if localFlake != null then localFlake else self;
  stackpanel-cli = pkgs.callPackage ../packages/stackpanel-cli (
    lib.optionalAttrs (sourceFlake ? lastModifiedDate || sourceFlake ? rev || sourceFlake ? dirtyRev) {
      flake = sourceFlake;
    }
  );

  # Extract serializable package info from devshell packages
  # This avoids slow nix eval at runtime by pre-computing during shell entry
  devshellPackages = cfg.devshell.packages or [ ];
  commandPkgs = cfg.devshell._commandPkgs or [ ];
  allPackages = devshellPackages ++ commandPkgs;

  # User-installed packages from .stack/data/packages.nix
  userPackagesCfg =
    cfg.userPackages or {
      enable = false;
      serialized = [ ];
    };
  userPackagesSerialized =
    if userPackagesCfg.enable or false then userPackagesCfg.serialized or [ ] else [ ];

  serializedDevshellPackages = map serialize.serializePackage allPackages;
  # Combine devshell packages with user packages (user packages already have source = "user")
  serializedPackages = serializedDevshellPackages ++ userPackagesSerialized;

  # =========================================================================
  # Missing flake inputs detection
  # =========================================================================
  # For each enabled module, check if its declared flakeInputs are present
  # in the flake's inputs. Produces a flat list for the CLI/MOTD to warn about.
  enabledModules = lib.filterAttrs (_: mod: mod.enable) (cfg.modules or { });

  allRequiredFlakeInputs = lib.concatLists (
    lib.mapAttrsToList (
      modName: mod: map (fi: fi // { requiredBy = modName; }) (mod.flakeInputs or [ ])
    ) enabledModules
  );

  missingFlakeInputs = builtins.filter (fi: !(inputs ? ${fi.name})) allRequiredFlakeInputs;

  # Both entrypoints use precisely the same module, action, panel and output
  # metadata. The shell adds only the fields needed by the CLI at runtime.
  fullConfig = publicState // {
    version = 1;
    projectName = portsCfg.project-name;
    projectRoot = "$STACKPANEL_ROOT"; # Will be expanded at runtime from PWD
    basePort = portsCfg.base-port;
    processComposePort = if pcCfg.port != null then pcCfg.port else portsCfg.base-port + 90;

    # Note: these must match the Go Paths struct fields (state/profile, keys, gen, data)
    paths = {
      state = dirs.profile;
      inherit (dirs) keys;
      inherit (dirs) gen;
      data = dirs.home;
    };

    # Port allocations are useful to the CLI even without a managed process.
    # Only explicitly owned services may opt in to the proxy.
    services =
      lib.listToAttrs (
        map (svc: {
          name = lib.toLower svc.key;
          value = {
            inherit (svc) key;
            name = svc.displayName;
            inherit (svc) port;
          };
        }) (lib.attrValues portsCfg.service)
      )
      // publicState.services;

    # Network configuration
    network = {
      step = {
        enable = cfg.network.step.enable or false;
        caUrl = cfg.network.step.caUrl or null;
      };
    };

    # IDE configuration
    ide = lib.optionalAttrs (ideCfg.enable && ideCfg.vscode.enable) {
      vscode = {
        enable = true;
        workspaceName = ideCfg.vscode.workspace-name;
        inherit (ideCfg.vscode) settings;
        inherit (ideCfg.vscode) extensions;
        extraFolders = ideCfg.vscode.extra-folders;
      };
    };

    # MOTD configuration (for CLI to render)
    motd = {
      inherit (cfg.motd) enable;
      inherit (cfg.motd) commands;
      inherit (cfg.motd) features;
      inherit (cfg.motd) hints;
    };

    # Installed packages (pre-serialized for fast runtime access)
    packages = serializedPackages;

    # Module requirements (what variables each module needs)
    # Serialized for agent/UI to show missing variables
    inherit (cfg) moduleRequirements;

    # Missing flake inputs that enabled modules require but aren't in the flake
    # Each entry: { name, url, followsNixpkgs, requiredBy }
    missingFlakeInputs = map (fi: {
      inherit (fi)
        name
        url
        followsNixpkgs
        requiredBy
        ;
    }) missingFlakeInputs;

    healthchecks = publicState.healthchecksList;

    # Runtime/repo checks need execution details. For build checks, cache
    # only the flake check name: even asking for drvPath instantiates the
    # derivation and its dependency graph. Resolve it on `doctor --build`.
    doctor = publicState.doctorList;

    # Adoption offers (flake-level and module-contributed), sorted for prompting.
    addons = cfg.addonsList or [ ];
  };

  # Serialize config to JSON
  configJson = builtins.toJSON fullConfig;

  # Write config to a store path.
  # Using pkgs.writeText instead of builtins.toFile to avoid store path issues
  # during complex flake evaluation.
  configFile = pkgs.writeText "stackpanel-config.json" configJson;
  proxyPortsFile = builtins.toFile "stackpanel-module-proxy-ports.json" (
    builtins.toJSON (serialize.proxyPortInventory (cfg.services or { }))
  );
in
{
  config = lib.mkIf cfg.enable {
    # Add the CLI to packages
    stackpanel.devshell.packages = [ stackpanel-cli ];

    # NOTE: MOTD hint for VS Code workspace is added by ide.nix

    # Call the CLI in enterShell to generate all files
    # Use mkBefore to ensure this runs early but after directory setup
    stackpanel.devshell.hooks.before = [
      ''
        # Warn if using STACKPANEL_CONFIG_OVERRIDE (prefer config.local.nix)
        if [[ -n "''${STACKPANEL_CONFIG_OVERRIDE:-}" ]]; then
          echo "⚠️  STACKPANEL_CONFIG_OVERRIDE is set - config.local.nix is preferred for local development" >&2
        fi

        # Generate stackpanel files via CLI
        # Read config from nix store, replace $STACKPANEL_ROOT with actual value
        export STACKPANEL_STATE_FILE="$STACKPANEL_STATE_DIR/stackpanel.json"
        _sp_config=$(cat ${configFile} | sed "s|\\\$STACKPANEL_ROOT|$STACKPANEL_ROOT|g")
        echo "$_sp_config" | ${stackpanel-cli}/bin/stack hook ${lib.optionalString cfg.cli.quiet "--quiet"}

        # Write the state file for Go agent/CLI consumption
        mkdir -p "$STACKPANEL_STATE_DIR"
        echo "$_sp_config" > "$STACKPANEL_STATE_FILE"
      ''
    ];

    stackpanel.devshell.hooks.after = [
      ''
        ${stackpanel-cli}/bin/stack preflight run ${lib.optionalString cfg.cli.quiet "--quiet"} && (
          # Publish the applied port inventory at the agent's fixed discovery
          # path. It is intentionally separate from the private CLI config.
          cd -- "''${STACKPANEL_ROOT:?project root required}" || exit 1
          for dir in .stack .stack/profile; do
            if [[ -L "$dir" ]]; then
              echo "Cannot publish module proxy inventory: $dir is a symbolic link" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/mkdir -p -- "$dir" || exit 1
          done
          ${pkgs.coreutils}/bin/ln -sfnT -- ${proxyPortsFile} .stack/profile/module-proxy-ports.json
        )
      ''
    ];

    # Export paths for other tools
    stackpanel.devshell.env = {
      # Path to the source Nix config file (for nix eval/import)
      STACKPANEL_NIX_CONFIG = "$STACKPANEL_ROOT/${dirs.home}/config.nix";
      # Path to the Nix-generated config JSON in the store (for Go CLI)
      STACKPANEL_CONFIG_JSON = "${configFile}";
    };
  };
}
