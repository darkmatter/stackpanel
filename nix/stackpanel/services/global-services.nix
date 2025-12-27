# ==============================================================================
# global-services.nix
#
# Global development services orchestration module for devenv.
#
# This module provides project-local database and infrastructure services
# with a shared Caddy reverse proxy. Each project can enable services that:
#   1. Provide required packages (psql, redis-cli, mc, etc.)
#   2. Set environment variables for connectivity (DATABASE_URL, etc.)
#   3. Use deterministic ports based on project name
#
# Service lifecycle management is handled by the stackpanel CLI:
#   stackpanel services start/stop/status
#
# Supported services:
#   - PostgreSQL: Database with automatic database creation
#   - Redis: Key-value store for caching and queues
#   - Minio: S3-compatible object storage
#   - Caddy: Reverse proxy with virtual hosts
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
  options,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.globalServices;
  portsCfg = config.stackpanel.ports;

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  coreGlobalServices = import ../core/services/global-services.nix {inherit pkgs lib;};

  gs = coreGlobalServices.mkGlobalServices {
    projectName = cfg.project-name;
    ports = portsCfg.service or {};
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
      stepEnabled = config.stackpanel.network.step.enable or false;
      stepCaUrl = config.stackpanel.network.step."ca-url" or "";
      stepCaFingerprint = config.stackpanel.network.step."ca-fingerprint" or "";
      projectName = cfg.project-name;
    };
  };
in {
  config = lib.mkIf cfg.enable ({
    # Ensure ports module uses the same project name
    stackpanel.ports.project-name = lib.mkDefault cfg.project-name;
  } // lib.optionalAttrs isDevenv {
    # Add all service packages (CLI binaries like psql, redis-cli, etc.)
    packages = gs.packages;

    # Set environment variables using computed ports
    env = gs.env;

    # Set shell hooks for each enabled service
    enterShell = lib.mkAfter gs.enterShell;
  });
}
