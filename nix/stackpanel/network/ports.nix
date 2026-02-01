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

  # Compute ports using shared library (attrset-based)
  servicesByKey = portsLib.computeServicesFromAttrset {
    projectName = cfg.project-name;
    services = cfg.services;
  };

  # Generate services config JSON
  servicesConfig = builtins.toJSON (
    lib.mapAttrsToList (key: svc: {
      inherit (svc) key port;
      name = svc.displayName;
    }) servicesByKey
  );

  # Get app info for MOTD display
  appsComputedCfg = config.stackpanel.appsComputed or { };
  hasApps = appsComputedCfg != { };
  hasServices = cfg.services != { };
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
          echo "" >&2
          echo "📦 Stackpanel Ports (project: ${cfg.project-name})" >&2
          echo "   Stable port: ${toString cfg.base-port}" >&2
          ${lib.optionalString hasApps ''
            echo "" >&2
            echo "   Apps:" >&2
            ${lib.concatMapStrings (
              name:
              let
                app = appsComputedCfg.${name};
              in
              ''
                echo "     ${name}: ${toString app.port}${
                  lib.optionalString (app.domain != null) " -> ${app.url}"
                }" >&2
              ''
            ) (lib.attrNames appsComputedCfg)}
          ''}
          ${lib.optionalString hasServices ''
            echo "" >&2
            echo "   Services:" >&2
            ${lib.concatMapStrings (svc: ''
              echo "     ${svc.displayName}: ${toString svc.port}" >&2
            '') (lib.attrValues servicesByKey)}
          ''}
          echo "" >&2
          echo "   Tip: Set STACKPANEL_QUIET=1 to hide this message" >&2
          echo "" >&2
        fi
      ''
    ];
  };
}
