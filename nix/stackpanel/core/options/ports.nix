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
#   - services: Attrset of infrastructure services needing ports
#
# Read-only computed values:
#   - base-port: The computed base port for the project
#   - service.<KEY>.port: Port for each service by key
#
# Port computation uses stablePort which hashes both project name and service
# name together, eliminating the need for index-based offsets.
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
  serviceType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Human-readable name for display (defaults to attrset key)";
          example = "PostgreSQL";
        };
      };
    }
  );
  # Compute base port using shared library
  basePort = portsLib.computeBasePort {
    name = cfg.project-name;
  };

  # Compute ports using shared library (attrset-based)
  servicesByKey = portsLib.computeServicesFromAttrset {
    projectName = cfg.project-name;
    services = cfg.services;
  };
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

    services = lib.mkOption {
      type = lib.types.attrsOf serviceType;
      default = { };
      description = ''
        Attrset of infrastructure services that need ports.
        Each service gets a deterministic port based on project name + service key.
        Provided via STACKPANEL_SERVICES_CONFIG (JSON).
      '';
      example = lib.literalExpression ''
        {
          POSTGRES = { name = "PostgreSQL"; };
          REDIS = { name = "Redis"; };
          MINIO = { name = "Minio"; };
          MINIO_CONSOLE = { name = "Minio Console"; };
        }
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
