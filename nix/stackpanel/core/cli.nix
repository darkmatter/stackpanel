# ==============================================================================
# cli.nix
#
# CLI-based file generation for stackpanel.
#
# This module aggregates configuration from various Stackpanel options and
# invokes the `stackpanel hook` CLI command when entering the devshell.
# All codegen is kicked off as a result of this invocation.
#
# Generated files (by CLI):
#   - .stackpanel/state/stackpanel.json (runtime state)
#   - .stackpanel/gen/ide/vscode/* (VS Code workspace, loader script)
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
  appsComputed = config.stackpanel.appsComputed or { };
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs =
    cfg.dirs or {
      home = ".stackpanel";
      state = ".stackpanel/state";
      gen = ".stackpanel/gen";
      config = ./.;
    };

  # Import the stackpanel CLI package
  stackpanel-cli = pkgs.callPackage ../packages/stackpanel-cli { };

  # Extract serializable package info from devshell packages
  # This avoids slow nix eval at runtime by pre-computing during shell entry
  devshellPackages = cfg.devshell.packages or [ ];
  commandPkgs = cfg.devshell._commandPkgs or [ ];
  allPackages = devshellPackages ++ commandPkgs;

  # User-installed packages from .stackpanel/data/packages.nix
  userPackagesCfg =
    cfg.userPackages or {
      enable = false;
      serialized = [ ];
    };
  userPackagesSerialized =
    if userPackagesCfg.enable or false then userPackagesCfg.serialized or [ ] else [ ];

  serializePackage =
    pkg:
    if builtins.isAttrs pkg then
      {
        name = pkg.pname or pkg.name or "unknown";
        version = pkg.version or "";
        attrPath = pkg.meta.mainProgram or pkg.pname or pkg.name or "";
        source = "devshell"; # From Nix config
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

  serializedDevshellPackages = map serializePackage allPackages;
  # Combine devshell packages with user packages (user packages already have source = "user")
  serializedPackages = serializedDevshellPackages ++ userPackagesSerialized;

  # The schema expected by the CLI should not be coupled to the actual Nix
  # options structure. We build a separate config object here.
  fullConfig = {
    version = 1;
    projectName = portsCfg.project-name;
    projectRoot = "$STACKPANEL_ROOT"; # Will be expanded at runtime from PWD
    basePort = portsCfg.base-port;
    processComposePort = if pcCfg.port != null then pcCfg.port else portsCfg.base-port + 90;

    # Note: these must match the Go Paths struct fields (state, gen, data)
    # dirs.config is intentionally excluded - it's a Nix-time path that becomes
    # a store path, and the CLI doesn't need it at runtime.
    paths = {
      state = dirs.state;
      gen = dirs.gen;
      data = dirs.home; # "data" in Go corresponds to dirs.home (.stackpanel)
    };

    # Apps with computed ports and domains
    apps = lib.mapAttrs (name: app: {
      port = app.port;
      domain = app.domain;
      url = app.url;
      tls = app.tls;
    }) appsComputed;

    # Services with ports
    services = lib.listToAttrs (
      map (svc: {
        name = lib.toLower svc.key;
        value = {
          key = svc.key;
          name = svc.displayName;
          port = svc.port;
        };
      }) (lib.attrValues portsCfg.service)
    );

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
        settings = ideCfg.vscode.settings;
        extensions = ideCfg.vscode.extensions;
        extraFolders = ideCfg.vscode.extra-folders;
      };
    };

    # MOTD configuration (for CLI to render)
    motd = {
      enable = cfg.motd.enable;
      commands = cfg.motd.commands;
      features = cfg.motd.features;
      hints = cfg.motd.hints;
    };

    # Installed packages (pre-serialized for fast runtime access)
    packages = serializedPackages;

    # Module requirements (what variables each module needs)
    # Serialized for agent/UI to show missing variables
    moduleRequirements = cfg.moduleRequirements;

    # UI configuration for the web interface
    ui = {
      # Extensions registered by modules (e.g., SST, CI, etc.)
      # Each extension can provide panels, feature flags, and per-app data
      # DEPRECATED: Use modules instead
      extensions = cfg.extensionsComputed or { };

      # Modules - the unified system for extending stackpanel
      # Replaces extensions with a more comprehensive module system
      modules = cfg.modulesComputed or { };
      modulesList = cfg.modulesList or [ ];

      # Module panels - serialized panel definitions for the web UI
      # These come from stackpanel.panels (set by each module's ui.nix)
      panels = cfg.panelsComputed or { };
      panelModules = cfg.panelModules or [ ];
    };
  };

  # Serialize config to JSON
  configJson = builtins.toJSON fullConfig;

  # Write config to a store path.
  # Using pkgs.writeText instead of builtins.toFile to avoid store path issues
  # during complex flake evaluation.
  configFile = pkgs.writeText "stackpanel-config.json" configJson;
in
{
  imports = [
    ./options
  ];

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
        echo "$_sp_config" | ${stackpanel-cli}/bin/stackpanel hook ${lib.optionalString cfg.cli.quiet "--quiet"}

        # Write the state file for Go agent/CLI consumption
        mkdir -p "$STACKPANEL_STATE_DIR"
        echo "$_sp_config" > "$STACKPANEL_STATE_FILE"
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
