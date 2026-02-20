# ==============================================================================
# global-services.nix
#
# Global development services orchestration module.
#
# This module maps `stackpanel.globalServices` (convenience layer) into
# `stackpanel.services` (canonical service type system). Services are then
# managed by process-compose under the "services" namespace.
#
# Supported services:
#   - PostgreSQL: Database with automatic database creation
#   - Redis: Key-value store for caching and queues
#   - Minio: S3-compatible object storage
#   - Caddy: Reverse proxy with virtual hosts (special case, not in PC)
#
# Usage:
#   stackpanel.globalServices = {
#     enable = true;
#     project-name = "myproject";
#     postgres = { enable = true; databases = ["mydb"]; };
#     redis.enable = true;
#     minio.enable = true;
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.globalServices;
  portsCfg = config.stackpanel.ports;

  # Import util for debug logging
  util = import ../lib/util.nix { inherit pkgs lib config; };

  coreGlobalServices = import ../core/services/global-services.nix { inherit pkgs lib; };

  # Compute the full gs bundle (needed for caddy and port resolution)
  gs = coreGlobalServices.mkGlobalServices {
    projectName = cfg.project-name;
    ports = portsCfg.service or { };
    postgres = {
      enable = cfg.postgres.enable;
      databases = cfg.postgres.databases;
      port = cfg.postgres.port;
      package = cfg.postgres.package;
    };
    redis = {
      enable = cfg.redis.enable;
      port = cfg.redis.port;
      package = cfg.redis.package;
    };
    minio = {
      enable = cfg.minio.enable;
      port = cfg.minio.port;
      consolePort = cfg.minio."console-port";
      package = cfg.minio.package;
    };
    caddy = {
      enable = cfg.caddy.enable;
      sites = cfg.caddy.sites;
      stepEnabled =
        (config.stackpanel.caddy.use-step-tls or false) && (config.stackpanel.step-ca.enable or false);
      stepCaUrl = config.stackpanel.step-ca.ca-url or "";
      stepCaFingerprint = config.stackpanel.step-ca.ca-fingerprint or "";
      projectName = cfg.project-name;
    };
  };
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # -------------------------------------------------------------------------
      # Common: ports, debug logging, caddy (stays as direct devshell)
      # -------------------------------------------------------------------------
      {
        # Ensure ports module uses the same project name
        stackpanel.ports.project-name = lib.mkDefault cfg.project-name;

        # Gum package for TUI prompts + caddy packages
        stackpanel.devshell.packages = [
          pkgs.gum
        ]
        ++ lib.optionals cfg.caddy.enable (gs.services.caddy.allPackages or [ ]);

        # Caddy env (if any)
        stackpanel.devshell.env = lib.optionalAttrs cfg.caddy.enable (gs.services.caddy.env or { });

        # Debug logging + caddy site registration hooks
        stackpanel.devshell.hooks.main = [
          ''
            ${util.log.debug "global-services: initializing services for ${cfg.project-name}"}
            ${lib.optionalString cfg.postgres.enable (
              util.log.debug "global-services: postgres enabled on port ${
                toString (portsCfg.service.POSTGRES.port or 5432)
              }"
            )}
            ${lib.optionalString cfg.redis.enable (util.log.debug "global-services: redis enabled")}
            ${lib.optionalString cfg.minio.enable (util.log.debug "global-services: minio enabled")}
          ''
          (lib.optionalString (cfg.caddy.enable && cfg.caddy.sites != { }) ''
            # Register this project's Caddy sites
            ${lib.concatMapStringsSep "\n" (site: ''
              ${gs.services.caddy.caddyAddSite}/bin/caddy-add-site "${site}" "${cfg.caddy.sites.${site}}" --project "${cfg.project-name}" 2>/dev/null || true
            '') (lib.attrNames cfg.caddy.sites)}
          '')
          ''
            ${util.log.debug "global-services: initialization complete"}
          ''
        ];
      }

      # -------------------------------------------------------------------------
      # PostgreSQL → stackpanel.services.postgres
      # -------------------------------------------------------------------------
      (lib.mkIf cfg.postgres.enable {
        stackpanel.services.postgres = {
          enable = true;
          displayName = "PostgreSQL";
          command = "${gs.services.postgres.startScript}/bin/postgres-start";
          port = gs.services.postgres.port;
          env = gs.services.postgres.env;
          packages = gs.services.postgres.allPackages;
          shellHook = gs.services.postgres.shellHook;
          dataDir = gs.services.postgres.dataDir;
          process-compose.readiness_probe = {
            exec.command = "${cfg.postgres.package}/bin/pg_isready -h ${gs.services.postgres.socketDir} -p ${toString gs.services.postgres.port}";
            initial_delay_seconds = 2;
            period_seconds = 5;
          };
        };
      })

      # -------------------------------------------------------------------------
      # Redis → stackpanel.services.redis
      # -------------------------------------------------------------------------
      (lib.mkIf cfg.redis.enable {
        stackpanel.services.redis = {
          enable = true;
          displayName = "Redis";
          command = "${gs.services.redis.startScript}/bin/redis-start";
          port = gs.services.redis.port;
          env = gs.services.redis.env;
          packages = gs.services.redis.allPackages;
          shellHook = gs.services.redis.shellHook;
          dataDir = gs.services.redis.dataDir;
          process-compose.readiness_probe = {
            exec.command = "${cfg.redis.package}/bin/redis-cli -p ${toString gs.services.redis.port} ping";
            initial_delay_seconds = 1;
            period_seconds = 3;
          };
        };
      })

      # -------------------------------------------------------------------------
      # Minio → stackpanel.services.minio
      # -------------------------------------------------------------------------
      (lib.mkIf cfg.minio.enable {
        stackpanel.services.minio = {
          enable = true;
          displayName = "Minio";
          description = "S3-compatible object storage";
          command = "${gs.services.minio.startScript}/bin/minio-start";
          port = gs.services.minio.port;
          env = gs.services.minio.env;
          packages = gs.services.minio.allPackages;
          shellHook = gs.services.minio.shellHook;
          dataDir = gs.services.minio.dataDir;
          process-compose.readiness_probe = {
            exec.command = "${pkgs.curl}/bin/curl -sf http://localhost:${toString gs.services.minio.port}/minio/health/live";
            initial_delay_seconds = 2;
            period_seconds = 5;
          };
        };
      })
    ]
  );
}
