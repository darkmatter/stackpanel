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
  portsLib = import ../lib/ports.nix { inherit lib; };

  # Service type for defining infrastructure services
  serviceType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''
            Human-readable service name shown in generated service metadata and UI surfaces.

            Defaults to the service attrset key, so `POSTGRES = { };` is valid. Set this when
            the key is machine-oriented but the display label should be clearer.
          '';
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
    inherit (cfg) services;
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
      description = ''
        Stable project identifier used as the input to deterministic port computation.

        Keep this value consistent across machines for the same repo. Changing it intentionally
        reassigns `stackpanel.ports.base-port` and every computed service port.
      '';
      example = "myapp";
    };

    services = lib.mkOption {
      type = lib.types.attrsOf serviceType;
      default = { };
      description = ''
        Infrastructure services that need deterministic local ports.

        Attr names are stable service keys, usually uppercase (`POSTGRES`, `REDIS`,
        `MINIO_CONSOLE`). Each key is hashed with `stackpanel.ports.project-name`, so adding
        or removing one service does not shift the others. Computed values are exposed under
        `stackpanel.ports.service.<KEY>.port` and emitted into computed variables such as
        `/computed/services/postgres/port` for generated env/config consumers.
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
      description = ''
        Read-only base port computed from `stackpanel.ports.project-name`.

        User app ports are allocated relative to this value by app modules. Service ports are
        computed per service key rather than by positional offsets, but this value remains the
        visible anchor for the project's local port range.
      '';
      example = 4200;
    };

    # Computed service ports lookup
    service = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
      default = servicesByKey;
      readOnly = true;
      description = ''
        Read-only computed service information keyed by `stackpanel.ports.services` attr name.

        Each value includes at least `name` and `port`. Use this when wiring service URLs,
        process-compose config, generated env vars, or health checks without hardcoding ports.
      '';
      example = lib.literalExpression ''
        {
          POSTGRES = { name = "PostgreSQL"; port = 4210; };
          REDIS = { name = "Redis"; port = 4211; };
        }
      '';
    };
  };

  # ===========================================================================
  # Contribute computed service ports to stackpanel.variables
  # ===========================================================================
  # Each infrastructure service gets a PORT variable that apps can reference.
  # These use the /computed/ prefix to indicate they are read-only.
  #
  # Example:
  #   config.stackpanel.variables."/computed/services/postgres/port".value  # "5432"
  # ===========================================================================
  config.stackpanel.variables = lib.mkIf cfg.enable (
    lib.mkMerge (
      lib.mapAttrsToList (
        serviceKey: serviceInfo:
        let
          # serviceKey is uppercase (e.g., "POSTGRES", "REDIS")
          # Create a lowercase version for the variable path
          lowerKey = lib.toLower serviceKey;
        in
        {
          # Port variable for each service (computed, read-only)
          "/computed/services/${lowerKey}/port" = {
            value = toString serviceInfo.port;
          };
        }
      ) servicesByKey
    )
  );
}
