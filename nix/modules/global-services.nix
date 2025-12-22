# Global Development Services Module for devenv
#
# This module provides project-local services (with global Caddy).
# Each project can enable services and they will:
# 1. Provide the required packages
# 2. Set environment variables for connectivity
# 3. Use deterministic ports based on project name
#
# All lifecycle management (start/stop/status) is handled by the stackpanel CLI:
#   stackpanel services start/stop/status
#
# Port Assignment:
#   Ports are computed from project name using stackpanel.ports.
#   By default, services use:
#     PostgreSQL: basePort + 0
#     Redis: basePort + 1
#     Minio: basePort + 2, console: basePort + 3
#
# Usage in devenv.nix:
#   stackpanel.globalServices = {
#     enable = true;
#     projectName = "stackpanel";
#
#     postgres = {
#       enable = true;
#       databases = ["stackpanel" "stackpanel_test"];
#     };
#
#     redis.enable = true;
#     minio.enable = true;
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.globalServices;
  portsCfg = config.stackpanel.ports;

  # Import the modular services library
  servicesLib = import ../lib/services {inherit pkgs lib;};

  # Helper to get port from service config or fall back to computed port
  getServicePort = key: explicitPort:
    if explicitPort != null
    then explicitPort
    else if portsCfg.service ? ${key}
    then portsCfg.service.${key}.port
    else throw "Service port '${key}' not found. Add it to stackpanel.ports.services list.";

  # Use computed ports from the ports module, or fall back to explicit overrides
  postgresPort = getServicePort "POSTGRES" cfg.postgres.port;
  redisPort = getServicePort "REDIS" cfg.redis.port;
  minioPort = getServicePort "MINIO" cfg.minio.port;
  minioConsolePort = getServicePort "MINIO_CONSOLE" cfg.minio.consolePort;

  # Create service instances if enabled
  postgres = lib.optionalAttrs cfg.postgres.enable (servicesLib.mkGlobalPostgres {
    projectName = cfg.projectName;
    databases = cfg.postgres.databases;
    port = postgresPort;
    package = cfg.postgres.package;
  });

  redis = lib.optionalAttrs cfg.redis.enable (servicesLib.mkGlobalRedis {
    projectName = cfg.projectName;
    port = redisPort;
    package = cfg.redis.package;
  });

  minio = lib.optionalAttrs cfg.minio.enable (servicesLib.mkGlobalMinio {
    projectName = cfg.projectName;
    port = minioPort;
    consolePort = minioConsolePort;
    package = cfg.minio.package;
  });

  # Get caddy scripts if caddy module is enabled
  caddyLib = import ../lib/caddy.nix {inherit pkgs lib;};
  caddyScripts = lib.optionalAttrs cfg.caddy.enable (caddyLib.mkCaddyScripts {
    stepEnabled = config.stackpanel.network.step.enable or false;
    stepCaUrl = config.stackpanel.network.step.caUrl or "";
    stepCaFingerprint = config.stackpanel.network.step.caFingerprint or "";
  });
in {
  options.stackpanel.globalServices = {
    enable = lib.mkEnableOption "Global singleton development services";

    projectName = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Project name used for registering databases and sites";
      example = "stackpanel";
    };

    postgres = {
      enable = lib.mkEnableOption "Global PostgreSQL service";

      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [cfg.projectName];
        description = "List of databases to create for this project";
        example = ["myapp" "myapp_test"];
      };

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "PostgreSQL port. If null, uses computed port from stackpanel.ports.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.postgresql_17;
        description = "PostgreSQL package to use";
      };
    };

    redis = {
      enable = lib.mkEnableOption "Global Redis service";

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Redis port. If null, uses computed port from stackpanel.ports.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.redis;
        description = "Redis package to use";
      };
    };

    minio = {
      enable = lib.mkEnableOption "Global Minio (S3) service";

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Minio API port. If null, uses computed port from stackpanel.ports.";
      };

      consolePort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Minio console port. If null, uses computed port from stackpanel.ports.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.minio;
        description = "Minio package to use";
      };
    };

    caddy = {
      enable = lib.mkEnableOption "Global Caddy reverse proxy";

      sites = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Sites to register with Caddy (domain -> upstream)";
        example = {
          "myapp.localhost" = "localhost:3000";
          "api.localhost" = "localhost:8080";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure ports module uses the same project name
    stackpanel.ports.projectName = lib.mkDefault cfg.projectName;

    # Add all service packages (CLI binaries like psql, redis-cli, etc.)
    packages =
      (lib.optionals cfg.postgres.enable postgres.allPackages)
      ++ (lib.optionals cfg.redis.enable redis.allPackages)
      ++ (lib.optionals cfg.minio.enable minio.allPackages)
      ++ (lib.optionals cfg.caddy.enable caddyScripts.allPackages);

    # Set environment variables using computed ports
    env = lib.mkMerge [
      (lib.optionalAttrs cfg.postgres.enable {
        PGHOST = "$HOME/.local/share/devservices/postgres/socket";
        PGPORT = toString postgresPort;
        DATABASE_URL = "postgresql://localhost:${toString postgresPort}/${lib.head cfg.postgres.databases}";
      })
      (lib.optionalAttrs cfg.redis.enable {
        REDIS_URL = "redis://localhost:${toString redisPort}";
      })
      (lib.optionalAttrs cfg.minio.enable {
        # NOTE: Do NOT set AWS_ENDPOINT_URL_S3 globally - it breaks AWS IAM auth.
        # Use MINIO_ENDPOINT or S3_ENDPOINT for apps that need Minio.
        MINIO_ENDPOINT = "http://localhost:${toString minioPort}";
        S3_ENDPOINT = "http://localhost:${toString minioPort}";
        MINIO_ROOT_USER = "minioadmin";
        MINIO_ROOT_PASSWORD = "minioadmin";
      })
    ];

    # Set shell hooks for each enabled service
    enterShell = lib.concatStringsSep "\n" (
      # PostgreSQL shell hook
      (lib.optional cfg.postgres.enable postgres.shellHook)
      ++
      # Redis shell hook
      (lib.optional cfg.redis.enable redis.shellHook)
      ++
      # Minio shell hook
      (lib.optional cfg.minio.enable minio.shellHook)
      ++
      # Register caddy sites
      (lib.optional (cfg.caddy.enable && cfg.caddy.sites != {}) ''
        # Register this project's Caddy sites
        ${lib.concatMapStringsSep "\n" (site: ''
          ${caddyScripts.caddyAddSite}/bin/caddy-add-site "${site}" "${cfg.caddy.sites.${site}}" --project "${cfg.projectName}" 2>/dev/null || true
        '') (lib.attrNames cfg.caddy.sites)}
      '')
    );
  };
}
