# CLI-based file generation for stackpanel
#
# This module builds the complete configuration and calls the Go CLI
# to generate all files in a single atomic operation. This ensures
# that generated files and state.json are always in sync.
#
# Generated files:
#   - .stackpanel/state/stackpanel.json (runtime state)
#   - .stackpanel/gen/ide/vscode/* (VS Code workspace, loader script)
#   - .stackpanel/gen/schemas/secrets/* (JSON schemas for YAML)
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel;
  portsCfg = config.stackpanel.ports;
  ideCfg = config.stackpanel.ide;
  appsComputed = config.stackpanel.appsComputed or {};

  # Import the stackpanel CLI package
  stackpanel-cli = pkgs.callPackage ../packages/stackpanel-cli {};

  # Import schemas module
  schemasLib = import ./secrets/schemas.nix {
    inherit lib;
    genDir = cfg.genDir;
  };
  schemas = schemasLib.generateSchemas;

  # Build the complete configuration for the CLI
  fullConfig = {
    version = 1;
    projectName = portsCfg.projectName;
    projectRoot = "$DEVENV_ROOT"; # Will be expanded at runtime
    basePort = portsCfg.basePort;

    paths = {
      state = cfg.stateDir;
      gen = cfg.genDir;
      data = cfg.dataDir;
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
        workspaceName = ideCfg.vscode.workspaceName;
        settings = ideCfg.vscode.settings;
        extensions = ideCfg.vscode.extensions;
        extraFolders = ideCfg.vscode.extraFolders;
      };
    };

    # Schemas configuration
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

  # Write config to a temp file in the nix store for shell to read
  configFile = pkgs.writeText "stackpanel-config.json" configJson;

in {
  options.stackpanel.cli = {
    enable = lib.mkEnableOption "CLI-based file generation" // {default = true;};

    quiet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Suppress generation output messages";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.cli.enable) {
    # Add the CLI to packages
    packages = [stackpanel-cli];

    # Add hints about IDE integration (if enabled)
    stackpanel.motd.hints = lib.mkIf (ideCfg.enable && ideCfg.vscode.enable) [
      "Open ${cfg.genDir}/ide/vscode/${ideCfg.vscode.workspaceName}.code-workspace in VS Code for integrated terminal"
    ];

    # Call the CLI in enterShell to generate all files
    # Use mkOrder to ensure this runs early but after directory setup
    enterShell = lib.mkOrder 450 ''
      # Generate stackpanel files via CLI
      # Read config from nix store, replace $DEVENV_ROOT with actual value
      _sp_config=$(cat ${configFile} | sed "s|\\\$DEVENV_ROOT|$DEVENV_ROOT|g")
      echo "$_sp_config" | ${stackpanel-cli}/bin/stackpanel init ${lib.optionalString cfg.cli.quiet "--quiet"}
    '';

    # Export paths for other tools
    env = {
      STACKPANEL_STATE_FILE = "\${STACKPANEL_STATE_DIR}/stackpanel.json";
      # Path to the Nix-generated config in the store (for nix eval to read)
      STACKPANEL_NIX_CONFIG = "${configFile}";
    };
  };
}
