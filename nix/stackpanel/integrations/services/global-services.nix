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
  dirs = config.stackpanel.dirs or { gen = ".stack/gen"; };

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
      # Common: ports, debug logging, caddy site generation + linking
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

        # Generate this project's Caddy site snippets functionally into
        # .stack/gen/caddy/. Generation is deterministic; `stackpanel caddy add`
        # (in hooks.after) only links them into the shared proxy.
        stackpanel.files.entries = lib.optionalAttrs (cfg.caddy.enable && cfg.caddy.sites != { }) (
          lib.mapAttrs' (
            domain: upstream:
            lib.nameValuePair "${dirs.gen}/caddy/${caddyLib.sanitizeDomain domain}.caddy" {
              format = "text";
              text = caddyLib.renderSite { inherit domain upstream; };
              source = "caddy";
              description = "Caddy reverse-proxy site ${domain}";
            }
          ) cfg.caddy.sites
        );

        # Debug logging
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
            ${util.log.debug "global-services: initialization complete"}
          ''
        ];

        # Link this project's generated Caddy snippets into the shared proxy.
        # Runs in `after` so the .stack/gen/caddy/ files (written by
        # `write-files` in `main`) already exist.
        stackpanel.devshell.hooks.after = lib.optional (cfg.caddy.enable && cfg.caddy.sites != { }) ''
          if command -v stackpanel >/dev/null 2>&1; then
            stackpanel caddy add >/dev/null 2>&1 || true
          fi
        '';
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
