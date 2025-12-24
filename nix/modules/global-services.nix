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
  options,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.globalServices;
  portsCfg = config.stackpanel.ports;

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  coreGlobalServices = import ../lib/core/global-services.nix {inherit pkgs lib;};

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
  options.stackpanel.globalServices = {
    enable = lib.mkEnableOption "Global singleton development services";

    project-name = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Project name used for registering databases and sites";
      example = "stackpanel";
    };

    postgres = {
      enable = lib.mkEnableOption "Global PostgreSQL service";

      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [cfg.project-name];
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

      console-port = lib.mkOption {
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
