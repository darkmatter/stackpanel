# Port computation utilities for devenv
#
# Provides deterministic port assignment based on project name.
# Apps and services use the base port and increment from there.
#
# The base port is computed as:
#   minPort + (hash(projectName) % portRange) - ((hash(projectName) % portRange) % modulus)
#
# This ensures the port is:
#   1. Deterministic (same name = same port)
#   2. Round (e.g., 3100 instead of 3174) for easier memorization
#   3. Unlikely to conflict with other projects
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
  pkgs,
  ...
}: let
  cfg = config.stackpanel.ports;

  # Compute the base port from project name
  # Uses MD5 hash of name, takes first 4 hex chars, converts to number
  # Then rounds to nearest modulus (default 100)
  computeBasePort = {
    name,
    minPort ? cfg.minPort,
    portRange ? cfg.portRange,
    modulus ? cfg.modulus,
  }: let
    hash = builtins.hashString "md5" name;
    rawOffset = lib.trivial.fromHexString (builtins.substring 0 4 hash);
    # Get offset within range, then round down to nearest modulus
    offsetInRange = lib.mod rawOffset portRange;
    roundedOffset = offsetInRange - (lib.mod offsetInRange modulus);
  in
    minPort + roundedOffset;

  # Compute port for this project
  basePort = computeBasePort {name = cfg.projectName;};

  # Services base offset (apps use 0-9, services use 10+)
  servicesBaseOffset = 10;

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

  # Compute ports for all services based on their index
  servicesWithPorts =
    lib.imap0 (idx: svc: {
      inherit (svc) key name;
      port = basePort + servicesBaseOffset + idx;
      displayName =
        if svc.name != ""
        then svc.name
        else svc.key;
    })
    cfg.services;

  # Create attrset for easy lookup: { POSTGRES = { port = ...; ... }; }
  servicesByKey = lib.listToAttrs (map (svc: {
      name = svc.key;
      value = svc;
    })
    servicesWithPorts);

  # Generate environment variables for all services
  serviceEnvVars = lib.listToAttrs (map (svc: {
      name = "STACKPANEL_${svc.key}_PORT";
      value = toString svc.port;
    })
    servicesWithPorts);

  # Get app info for MOTD display
  appsComputedCfg = config.stackpanel.appsComputed or {};
  hasApps = appsComputedCfg != {};
  hasServices = cfg.services != [];
in {
  options.stackpanel.ports = {
    enable = lib.mkEnableOption "Automatic port assignment" // {default = true;};

    projectName = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Project name used for port computation. Set this to match your project name.";
      example = "myapp";
    };

    minPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Minimum port number for the port range";
    };

    portRange = lib.mkOption {
      type = lib.types.int;
      default = 7000;
      description = "Range of ports to use (minPort to minPort + portRange)";
    };

    modulus = lib.mkOption {
      type = lib.types.int;
      default = 100;
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
    basePort = lib.mkOption {
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

  config = lib.mkIf cfg.enable {
    # Expose computed ports as environment variables
    env =
      {
        STACKPANEL_BASE_PORT = toString cfg.basePort;
      }
      // serviceEnvVars;

    # Print port info in shell MOTD
    enterShell = lib.mkAfter ''
      # Display port information
      if [[ -z "$STACKPANEL_QUIET" ]]; then
        echo ""
        echo "📦 Stackpanel Ports (project: ${cfg.projectName})"
        echo "   Base port: ${toString cfg.basePort}"
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
  };
}
