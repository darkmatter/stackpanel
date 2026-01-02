# ==============================================================================
# ports.nix
#
# Deterministic port assignment module for devenv projects.
#
# This module computes stable ports based on project name, ensuring each
# project gets consistent port assignments across machines. Ports are
# exposed as environment variables for easy access.
#
# Port Layout (from basePort):
#   +0 to +9:   User apps (defined in stackpanel.apps)
#   +10 to +99: Infrastructure services (postgres, redis, minio, etc.)
#
# Example:
#   projectName = "myapp" -> basePort = 3100
#   Web app: 3100, Server: 3101, Docs: 3102
#   PostgreSQL: 3110, Redis: 3111, Minio: 3112
#
# Environment variables are generated as STACKPANEL_STABLE_PORT and
# STACKPANEL_SERVICES_CONFIG (JSON).
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.ports;

  # Import shared port computation library
  portsLib = import ../lib/ports.nix { inherit lib; };

  # Compute ports using shared library
  servicesWithPorts = portsLib.computeServicesWithPorts {
    basePort = cfg.base-port;
    services = cfg.services;
  };

  # Generate services config JSON using shared library
  servicesConfig = portsLib.mkServicesConfig servicesWithPorts;

  # Get app info for MOTD display
  appsComputedCfg = config.stackpanel.appsComputed or { };
  hasApps = appsComputedCfg != { };
  hasServices = cfg.services != [ ];
in
{
  config = lib.mkIf cfg.enable {
    # Expose computed ports as environment variables
    stackpanel.devshell.env = {
      STACKPANEL_STABLE_PORT = toString cfg.base-port;
      STACKPANEL_SERVICES_CONFIG = servicesConfig;
    };

    # Print port info in shell MOTD
    stackpanel.devshell.hooks.after = [
      ''
        # Display port information
        if [[ -z "''${STACKPANEL_QUIET:-}" ]]; then
          echo ""
          echo "📦 Stackpanel Ports (project: ${cfg.project-name})"
          echo "   Stable port: ${toString cfg.base-port}"
          ${lib.optionalString hasApps ''
            echo ""
            echo "   Apps:"
            ${lib.concatMapStrings (
              name:
              let
                app = appsComputedCfg.${name};
              in
              ''
                echo "     ${name}: ${toString app.port}${lib.optionalString (app.domain != null) " -> ${app.url}"}"
              ''
            ) (lib.attrNames appsComputedCfg)}
          ''}
          ${lib.optionalString hasServices ''
            echo ""
            echo "   Services:"
            ${lib.concatMapStrings (svc: ''
              echo "     ${svc.displayName}: ${toString svc.port}"
            '') servicesWithPorts}
          ''}
          echo ""
          echo "   Tip: Set STACKPANEL_QUIET=1 to hide this message"
          echo ""
        fi
      ''
    ];
  };
}
