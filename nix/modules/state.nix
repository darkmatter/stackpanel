# State file generation for stackpanel
#
# Generates a JSON state file in .stackpanel/state/stackpanel.json
# This file is used by the Go CLI and agent to understand the current
# devenv configuration without needing to evaluate Nix.
#
# The state file includes:
#   - Project metadata (name, base port)
#   - Apps with ports and domains
#   - Services with ports
#   - Paths to state/gen directories
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel;
  portsCfg = config.stackpanel.ports;
  appsComputed = config.stackpanel.appsComputed or {};

  # Build the state object
  stateData = {
    # Metadata
    version = 1;
    projectName = portsCfg.project-name;
    basePort = portsCfg.base-port;

    # Directories (relative paths - CLI will resolve to absolute)
    paths = {
      state = cfg.state-dir;
      gen = cfg.gen-dir;
      data = cfg.data-dir;
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
        caUrl = cfg.network.step.ca-url or null;
      };
    };
  };

  # Generate JSON
  stateJson = builtins.toJSON stateData;
  stateFile = pkgs.writeText "stackpanel-state.json" stateJson;
in {
  options.stackpanel.state = {
    enable = lib.mkEnableOption "state file generation" // {default = true;};

    file = lib.mkOption {
      type = lib.types.str;
      default = "stackpanel.json";
      description = "Name of the state file in stateDir";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.state.enable && !(cfg.cli.enable or false)) {
    # Write state file on shell entry
    # NOTE: This is disabled when stackpanel.cli.enable = true (CLI handles generation)
    enterShell = lib.mkAfter ''
      # Write stackpanel state file for CLI/agent consumption
      mkdir -p "$STACKPANEL_STATE_DIR"
      cat > "$STACKPANEL_STATE_DIR/${cfg.state.file}" << 'STACKPANEL_STATE_EOF'
${stateJson}
STACKPANEL_STATE_EOF
    '';

    # Export state file path
    env.STACKPANEL_STATE_FILE = "\${STACKPANEL_STATE_DIR}/${cfg.state.file}";
  };
}
