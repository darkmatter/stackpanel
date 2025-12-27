# ==============================================================================
# state.nix
#
# State file generation for stackpanel (legacy mode).
#
# Generates a JSON state file in .stackpanel/state/stackpanel.json that is
# used by the Go CLI and agent to understand the current devenv configuration
# without needing to evaluate Nix.
#
# The state file includes:
#   - Project metadata (name, base port)
#   - Apps with ports and domains
#   - Services with ports
#   - Paths to state/gen directories
#   - Network configuration (Step CA settings)
#
# NOTE: This module is disabled when stackpanel.cli.enable = true, as the
# CLI handles state file generation directly. This provides backward
# compatibility for setups that don't use the CLI.
#
# Enable with: stackpanel.state.enable = true (when cli.enable = false)
# ==============================================================================
{
  lib,
  config,
  options,
  pkgs,
  ...
}: let
  cfg = config.stackpanel;
  portsCfg = config.stackpanel.ports or { project-name = "unknown"; base-port = 5000; };
  appsComputed = config.stackpanel.appsComputed or {};
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = cfg.dirs or { home = ".stackpanel"; state = ".stackpanel/state"; gen = ".stackpanel/gen"; config = ./.; };

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  # Build the state object
  stateData = {
    # Metadata
    version = 1;
    projectName = portsCfg.project-name;
    basePort = portsCfg.base-port;

    # Directories
    paths = {
      root = dirs.home;
      state = dirs.state;
      gen = dirs.gen;
      config = toString dirs.config;
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
  imports = [
    ./options
  ];

  config = lib.mkIf (cfg.enable && cfg.state.enable && !(cfg.cli.enable or false)) (lib.optionalAttrs isDevenv {
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
  });
}
