# Port computation module for devenv
#
# Provides deterministic port assignment based on project name.
# Uses shared core library for computation logic.
#
# Apps and services use the base port and increment from there.
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
# Services are defined generically via stackpanel.ports.services list
#
{
  lib,
  config,
  options,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.ports;

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  # Import shared port computation library
  portsLib = import ../lib/core/ports.nix { inherit lib; };

  # Compute base port using shared library
  basePort = portsLib.computeBasePort {
    name = cfg.project-name;
    minPort = cfg.min-port;
    portRange = cfg.port-range;
    modulus = cfg.modulus;
  };

  # Service type for defining infrastructure services
  serviceType = lib.types.submodule {
    options = {
      key = lib.mkOption {
        type = lib.types.str;
        description = "Unique key for the service (used in env var: STACKPANEL_<KEY>_PORT)";
        example = "POSTGRES";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable name for display";
        example = "PostgreSQL";
      };
    };
  };

  # Compute ports using shared library
  servicesWithPorts = portsLib.computeServicesWithPorts {
    inherit basePort;
    services = cfg.services;
  };

  # Create attrset for easy lookup using shared library
  servicesByKey = portsLib.mkServicesByKey servicesWithPorts;

  # Generate environment variables using shared library
  serviceEnvVars = portsLib.mkServiceEnvVars servicesWithPorts;

  # Get app info for MOTD display
  appsComputedCfg = config.stackpanel.appsComputed or {};
  hasApps = appsComputedCfg != {};
  hasServices = cfg.services != [];
in {
  options.stackpanel.ports = {
    enable = lib.mkEnableOption "Automatic port assignment" // {default = true;};

    project-name = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Project name used for port computation. Set this to match your project name.";
      example = "myapp";
    };

    min-port = lib.mkOption {
      type = lib.types.port;
      default = portsLib.defaults.minPort;
      description = "Minimum port number for the port range";
    };

    port-range = lib.mkOption {
      type = lib.types.int;
      default = portsLib.defaults.portRange;
      description = "Range of ports to use (min-port to min-port + port-range)";
    };

    modulus = lib.mkOption {
      type = lib.types.int;
      default = portsLib.defaults.modulus;
      description = ''
        Port rounding modulus. Ports are rounded to nearest multiple.
        Use 100 for ports like 3100, 3200, 3300.
        Use 10 for ports like 3110, 3120, 3130 (if collision occurs).
      '';
      example = 10;
    };

    services = lib.mkOption {
      type = lib.types.listOf serviceType;
      default = [];
      description = ''
        List of infrastructure services that need ports.
        Each service gets a port at basePort + 10 + index.
        Environment variable: STACKPANEL_<KEY>_PORT
      '';
      example = lib.literalExpression ''
        [
          { key = "POSTGRES"; name = "PostgreSQL"; }
          { key = "REDIS"; name = "Redis"; }
          { key = "MINIO"; name = "Minio"; }
          { key = "MINIO_CONSOLE"; name = "Minio Console"; }
        ]
      '';
    };

    # Computed values (read-only)
    base-port = lib.mkOption {
      type = lib.types.port;
      default = basePort;
      readOnly = true;
      description = "The computed base port for this project";
    };

    # Computed service ports lookup
    service = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
      default = servicesByKey;
      readOnly = true;
      description = ''
        Computed service information by key.
        Access: config.stackpanel.ports.service.POSTGRES.port
      '';
    };
  };

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
