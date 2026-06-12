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
  util = import ../../lib/util.nix { inherit pkgs lib config; };

  servicesLib = import ./lib.nix { inherit pkgs lib; };
  caddyLib = import ./caddy { inherit pkgs lib; };
  coreGlobalServices = import ../../core/lib/global-services.nix {
    inherit
      pkgs
      lib
      servicesLib
      caddyLib
      ;
  };

  # Compute the full gs bundle (needed for caddy and port resolution)
  gs = coreGlobalServices.mkGlobalServices {
    projectName = cfg.project-name;
    ports = portsCfg.service or { };
    postgres = {
      inherit (cfg.postgres) enable;
      inherit (cfg.postgres) databases;
      inherit (cfg.postgres) port;
      inherit (cfg.postgres) package;
    };
    redis = {
      inherit (cfg.redis) enable;
      inherit (cfg.redis) port;
      inherit (cfg.redis) package;
    };
    minio = {
      inherit (cfg.minio) enable;
      inherit (cfg.minio) port;
      consolePort = cfg.minio."console-port";
      inherit (cfg.minio) package;
    };
    caddy = {
      inherit (cfg.caddy) enable;
      inherit (cfg.caddy) sites;
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
          inherit (gs.services.postgres) port;
          inherit (gs.services.postgres) env;
          packages = gs.services.postgres.allPackages;
          inherit (gs.services.postgres) shellHook;
          inherit (gs.services.postgres) dataDir;
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
          inherit (gs.services.redis) port;
          inherit (gs.services.redis) env;
          packages = gs.services.redis.allPackages;
          inherit (gs.services.redis) shellHook;
          inherit (gs.services.redis) dataDir;
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
          inherit (gs.services.minio) port;
          inherit (gs.services.minio) env;
          packages = gs.services.minio.allPackages;
          inherit (gs.services.minio) shellHook;
          inherit (gs.services.minio) dataDir;
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
