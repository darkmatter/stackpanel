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
# Environment variables are generated as STACKPANEL_BASE_PORT and
# service-specific vars like PORT_POSTGRES, PORT_REDIS, etc.
# ==============================================================================
{
  lib,
  config,
  options,
  ...
}: let
  cfg = config.stackpanel.ports;

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  # Import shared port computation library
  portsLib = import ../lib/core/ports.nix { inherit lib; };

  # Compute ports using shared library
  servicesWithPorts = portsLib.computeServicesWithPorts {
    basePort = cfg.base-port;
    services = cfg.services;
  };

  # Generate environment variables using shared library
  serviceEnvVars = portsLib.mkServiceEnvVars servicesWithPorts;

  # Get app info for MOTD display
  appsComputedCfg = config.stackpanel.appsComputed or {};
  hasApps = appsComputedCfg != {};
  hasServices = cfg.services != [];
in {
  config = lib.mkIf cfg.enable (lib.optionalAttrs isDevenv {
    # Expose computed ports as environment variables
    env =
      {
        STACKPANEL_BASE_PORT = toString cfg.base-port;
      }
      // serviceEnvVars;

    # Print port info in shell MOTD
    enterShell = lib.mkAfter ''
      # Display port information
      if [[ -z "$STACKPANEL_QUIET" ]]; then
        echo ""
        echo "📦 Stackpanel Ports (project: ${cfg.project-name})"
        echo "   Base port: ${toString cfg.base-port}"
        ${lib.optionalString hasApps ''
        echo ""
        echo "   Apps:"
        ${lib.concatMapStrings (name: let
          app = appsComputedCfg.${name};
        in ''
          echo "     ${name}: ${toString app.port}${lib.optionalString (app.domain != null) " -> ${app.url}"}"
        '') (lib.attrNames appsComputedCfg)}
      ''}
        ${lib.optionalString hasServices ''
        echo ""
        echo "   Services:"
        ${lib.concatMapStrings (svc: ''
            echo "     ${svc.displayName}: ${toString svc.port}"
          '')
          servicesWithPorts}
      ''}
        echo ""
        echo "   Tip: Set STACKPANEL_QUIET=1 to hide this message"
        echo ""
      fi
    '';
  });
}
