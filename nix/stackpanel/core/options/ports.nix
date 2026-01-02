# ==============================================================================
# ports.nix
#
# Port computation options - deterministic port assignment from project name.
#
# Provides declarative port assignment based on project name, ensuring each
# project gets consistent ports across all developer machines.
#
# Port Layout (from basePort):
#   +0 to +9:   User apps (defined in stackpanel.apps)
#   +10 to +99: Infrastructure services (postgres, redis, minio, etc.)
#
# Options:
#   - enable: Enable automatic port assignment (default: true)
#   - project-name: Project name for port computation
#   - min-port: Minimum port number (default: 3000)
#   - port-range: Range size (default: 7000)
#   - modulus: Rounding modulus for memorable ports (default: 100)
#   - services: List of infrastructure services needing ports
#
# Read-only computed values:
#   - base-port: The computed base port for the project
#   - service.<KEY>.port: Port for each service by key
#
# Uses shared core library (../services/ports.nix) for computation logic.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.ports;

  # Import shared port computation library
  portsLib = import ../../lib/ports.nix { inherit lib; };

  # Service type for defining infrastructure services
  serviceType = lib.types.submodule {
    options = {
      key = lib.mkOption {
        type = lib.types.str;
        description = "Unique key for the service (used in generated services config)";
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
  # Compute base port using shared library
  basePort = portsLib.computeBasePort {
    name = cfg.project-name;
    minPort = cfg.min-port;
    portRange = cfg.port-range;
    modulus = cfg.modulus;
  };
  # Compute ports using shared library
  servicesWithPorts = portsLib.computeServicesWithPorts {
    inherit basePort;
    services = cfg.services;
  };

  # Create attrset for easy lookup using shared library
  servicesByKey = portsLib.mkServicesByKey servicesWithPorts;
in
{
  options.stackpanel.ports = {
    enable = lib.mkEnableOption "Automatic port assignment" // {
      default = true;
    };

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
      default = [ ];
      description = ''
        List of infrastructure services that need ports.
        Each service gets a port at basePort + 10 + index.
        Provided via STACKPANEL_SERVICES_CONFIG (JSON).
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
}
