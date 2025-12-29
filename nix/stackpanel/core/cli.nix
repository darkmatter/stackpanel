# ==============================================================================
# cli.nix
#
# CLI-based file generation for stackpanel.
#
# This module aggregates configuration from various Stackpanel options and
# invokes the `stackpanel init` CLI command when entering the devshell.
# All codegen is kicked off as a result of this invocation.
#
# Generated files (by CLI):
#   - .stackpanel/state/stackpanel.json (runtime state)
#   - .stackpanel/gen/ide/vscode/* (VS Code workspace, loader script)
#   - .stackpanel/gen/schemas/secrets/* (JSON schemas from Nix definitions)
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
}: let
  cfg = config.stackpanel;
  portsCfg = config.stackpanel.ports or { project-name = "unknown"; base-port = 5000; };
  ideCfg = config.stackpanel.ide or { enable = false; vscode = { enable = false; workspace-name = "workspace"; }; };
  appsComputed = config.stackpanel.appsComputed or {};
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = cfg.dirs or { home = ".stackpanel"; state = ".stackpanel/state"; gen = ".stackpanel/gen"; config = ./.; };



  # Import the stackpanel CLI package
  stackpanel-cli = pkgs.callPackage ../packages/stackpanel-cli {};

  # Import schemas from the secrets module (single source of truth)
  schemasLib = import ../secrets/schemas.nix { inherit lib; };
  schemas = schemasLib.allSchemas;

  # The schema expected by the CLI should not be coupled to the actual Nix
  # options structure. We build a separate config object here.
  fullConfig = {
    version = 1;
    projectName = portsCfg.project-name;
    projectRoot = "$STACKPANEL_ROOT"; # Will be expanded at runtime from PWD
    basePort = portsCfg.base-port;

    # Note: these must match the Go Paths struct fields (state, gen, data)
    # dirs.config is intentionally excluded - it's a Nix-time path that becomes
    # a store path, and the CLI doesn't need it at runtime.
    paths = {
      state = dirs.state;
      gen = dirs.gen;
      data = dirs.home;  # "data" in Go corresponds to dirs.home (.stackpanel)
    };

    # Apps with computed ports and domains
    apps = lib.mapAttrs (name: app: {
      port = app.port;
      domain = app.domain;
      url = app.url;
      tls = app.tls;
    }) appsComputed;

    # Services with ports
    services = lib.listToAttrs (map (svc: {
      name = lib.toLower svc.key;
      value = {
        key = svc.key;
        name = svc.displayName;
        port = svc.port;
        envVar = "STACKPANEL_${svc.key}_PORT";
      };
    }) (lib.attrValues portsCfg.service));

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

    # Schemas for YAML config validation (generated from Nix definitions)
    schemas = {
      secrets = {
        config = schemas."config.schema.json";
        users = schemas."users.schema.json";
        appConfig = schemas."app-config.schema.json";
        schema = schemas."schema.schema.json";
        env = schemas."env.schema.json";
      };
    };

    # MOTD configuration (for CLI to render)
    motd = {
      enable = cfg.motd.enable;
      commands = cfg.motd.commands;
      features = cfg.motd.features;
      hints = cfg.motd.hints;
    };
  };

  # Serialize config to JSON
  configJson = builtins.toJSON fullConfig;

  # Write config to a store path.
  # Using builtins.toFile (no builder needed) since we no longer embed store path references.
  configFile = builtins.toFile "stackpanel-config.json" configJson;

in {
  imports = [
    ./options
  ];

  config = lib.mkIf (cfg.enable && cfg.cli.enable) {
    # Add the CLI to packages
    stackpanel.devshell.packages = [stackpanel-cli];

    # Add hints about IDE integration (if enabled)
    stackpanel.motd.hints = lib.mkIf (ideCfg.enable && ideCfg.vscode.enable) [
      "Open ${dirs.gen}/ide/vscode/${ideCfg.vscode.workspace-name}.code-workspace in VS Code for integrated terminal"
    ];

    # Call the CLI in enterShell to generate all files
    # Use mkBefore to ensure this runs early but after directory setup
    stackpanel.devshell.hooks.before = [
      ''
        # Generate stackpanel files via CLI
        # Read config from nix store, replace $STACKPANEL_ROOT with actual value
        _sp_config=$(cat ${configFile} | sed "s|\\\$STACKPANEL_ROOT|$STACKPANEL_ROOT|g")
        echo "$_sp_config" | ${stackpanel-cli}/bin/stackpanel init ${lib.optionalString cfg.cli.quiet "--quiet"}
      ''
    ];

    # Export paths for other tools
    stackpanel.devshell.env = {
      STACKPANEL_STATE_FILE = "\${STACKPANEL_STATE_DIR}/stackpanel.json";
      # Path to the Nix-generated config in the store (for nix eval to read)
      STACKPANEL_NIX_CONFIG = "${configFile}";
    };
  };
}
