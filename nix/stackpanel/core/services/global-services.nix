# ==============================================================================
# global-services.nix
#
# Global singleton development services configuration.
#
# This module provides a unified interface for configuring development services
# (PostgreSQL, Redis, Minio, Caddy) that run as global singletons on the system.
# Services share state across all projects to avoid resource duplication.
#
# Features:
#   - Port resolution from explicit values, stackpanel.ports, or defaults
#   - Environment variables for service connections (DATABASE_URL, REDIS_URL, etc.)
#   - Shell hooks for service initialization
#   - Caddy site registration for reverse proxy
#
# Works in both `nix develop` (mkShell) and `devenv shell` contexts.
#
# Usage:
#   globalServices.mkGlobalServices {
#     projectName = "myapp";
#     postgres.enable = true;
#     redis.enable = true;
#   }
# ==============================================================================
{
  pkgs,
  lib,
}:
let
  servicesLib = import ./services.nix { inherit pkgs lib; };
  caddyLib = import ../../services/caddy { inherit pkgs lib; };

  # Fallback ports when explicit or computed ports are not provided
  fallbackPorts = {
    POSTGRES = servicesLib.defaultPorts.postgres;
    REDIS = servicesLib.defaultPorts.redis;
    MINIO = servicesLib.defaultPorts.minio;
    MINIO_CONSOLE = servicesLib.defaultPorts."minio-console";
  };

  # Resolve a service port using (in order):
  # 1) Explicit value
  # 2) Ports attrset (from stackpanel.ports)
  # 3) Service default
  getPort =
    {
      key,
      explicit,
      ports,
    }:
    if explicit != null then
      explicit
    else if builtins.hasAttr key ports && (ports.${key} ? port) then
      ports.${key}.port
    else
      fallbackPorts.${key};
in
{
  # Shared implementation for global dev services.
  # Works in both `nix develop` (mkShell) and `devenv shell`.
  mkGlobalServices =
    {
      projectName,
      ports ? { },
      postgres ? { },
      redis ? { },
      minio ? { },
      caddy ? { },
    }:
    let
      defaults = {
        postgres = {
          enable = false;
          databases = null;
          port = null;
          package = pkgs.postgresql_17;
        };
        redis = {
          enable = false;
          port = null;
          package = pkgs.redis;
        };
        minio = {
          enable = false;
          port = null;
          consolePort = null;
          package = pkgs.minio;
        };
        caddy = {
          enable = false;
          sites = { };
          stepEnabled = false;
          stepCaUrl = "";
          stepCaFingerprint = "";
          projectName = projectName;
        };
      };

      cfg = lib.recursiveUpdate defaults {
        inherit projectName;
        postgres = postgres;
        redis = redis;
        minio = minio;
        caddy = caddy;
      };

      databases = if cfg.postgres.databases == null then [ cfg.projectName ] else cfg.postgres.databases;

      postgresPort = getPort {
        key = "POSTGRES";
        explicit = cfg.postgres.port;
        inherit ports;
      };
      redisPort = getPort {
        key = "REDIS";
        explicit = cfg.redis.port;
        inherit ports;
      };
      minioPort = getPort {
        key = "MINIO";
        explicit = cfg.minio.port;
        inherit ports;
      };
      minioConsolePort = getPort {
        key = "MINIO_CONSOLE";
        explicit = cfg.minio.consolePort;
        inherit ports;
      };

      postgresService = lib.optionalAttrs cfg.postgres.enable (
        servicesLib.mkGlobalPostgres {
          projectName = cfg.projectName;
          databases = databases;
          port = postgresPort;
          package = cfg.postgres.package;
        }
      );

      redisService = lib.optionalAttrs cfg.redis.enable (
        servicesLib.mkGlobalRedis {
          projectName = cfg.projectName;
          port = redisPort;
          package = cfg.redis.package;
        }
      );

      minioService = lib.optionalAttrs cfg.minio.enable (
        servicesLib.mkGlobalMinio {
          projectName = cfg.projectName;
          port = minioPort;
          consolePort = minioConsolePort;
          package = cfg.minio.package;
        }
      );

      caddyScripts = lib.optionalAttrs cfg.caddy.enable (
        caddyLib.mkCaddyScripts {
          stepEnabled = cfg.caddy.stepEnabled;
          stepCaUrl = cfg.caddy.stepCaUrl;
          stepCaFingerprint = cfg.caddy.stepCaFingerprint;
        }
      );

      # Placeholder controller for future lifecycle orchestration
      controller = {
        name = "stackpanel-devservices";
        allPackages = [ ];
        shellHook = "";
      };

      packages =
        (lib.optionals cfg.postgres.enable postgresService.allPackages)
        ++ (lib.optionals cfg.redis.enable redisService.allPackages)
        ++ (lib.optionals cfg.minio.enable minioService.allPackages)
        ++ (lib.optionals cfg.caddy.enable caddyScripts.allPackages)
        ++ controller.allPackages;

      shellHook = lib.concatStringsSep "\n" (
        [
          "# Stackpanel global services initialization"
        ]
        ++ lib.optional cfg.postgres.enable postgresService.shellHook
        ++ lib.optional cfg.redis.enable redisService.shellHook
        ++ lib.optional cfg.minio.enable minioService.shellHook
        ++ lib.optional (cfg.caddy.enable && cfg.caddy.sites != { }) ''
          # Register this project's Caddy sites
          ${lib.concatMapStringsSep "\n" (site: ''
            ${caddyScripts.caddyAddSite}/bin/caddy-add-site "${site}" "${cfg.caddy.sites.${site}}" --project "${cfg.caddy.projectName}" 2>/dev/null || true
          '') (lib.attrNames cfg.caddy.sites)}
        ''
        ++ [
          ""
          "# Run 'stackpanel --help' to see available commands"
        ]
      );

      env = lib.mergeAttrsList [
        (lib.optionalAttrs cfg.postgres.enable {
          PGHOST = "$HOME/.local/share/devservices/postgres/socket";
          PGPORT = toString postgresPort;
          DATABASE_URL = "postgresql://localhost:${toString postgresPort}/${lib.head databases}";
        })
        (lib.optionalAttrs cfg.redis.enable {
          REDIS_URL = "redis://localhost:${toString redisPort}";
        })
        (lib.optionalAttrs cfg.minio.enable {
          MINIO_ENDPOINT = "http://localhost:${toString minioPort}";
          S3_ENDPOINT = "http://localhost:${toString minioPort}";
          MINIO_ROOT_USER = "minioadmin";
          MINIO_ROOT_PASSWORD = "minioadmin";
        })
      ];
    in
    {
      inherit packages shellHook env;
      enterShell = shellHook;

      services = {
        postgres = postgresService;
        redis = redisService;
        minio = minioService;
        caddy = caddyScripts;
        inherit controller;
      };

      # Helper mkShell for callers that want a full shell attrset
      shell = pkgs.mkShell (
        {
          inherit packages shellHook;
        }
        // env
      );
    };
}
