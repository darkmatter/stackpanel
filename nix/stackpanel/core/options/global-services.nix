# ==============================================================================
# global-services.nix
#
# Global development services options - PostgreSQL, Redis, Minio, Caddy.
#
# Configures global singleton development services that are shared across
# all projects on the system. This avoids running multiple instances of
# heavy services like PostgreSQL.
#
# Options:
#   - enable: Enable global singleton development services
#   - project-name: Project name for database/site registration
#   - postgres: PostgreSQL configuration (databases, port, package)
#   - redis: Redis configuration (port, package)
#   - minio: Minio S3 configuration (port, console-port, package)
#   - caddy: Caddy reverse proxy configuration (sites)
#
# Usage:
#   stackpanel.globalServices = {
#     enable = true;
#     postgres.enable = true;
#     postgres.databases = ["myapp" "myapp_test"];
#   };
#
# Note: pkgs is optional. Package defaults are set in config when pkgs is available.
# ==============================================================================
{
  lib,
  config,
  ...
}@args:
let
  # Check if pkgs was provided without triggering a lookup error
  hasPkgs = args ? pkgs;
  pkgs = args.pkgs or null;

  cfg = config.stackpanel.globalServices;
in
{
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
        default = [ cfg.project-name ];
        description = "List of databases to create for this project";
        example = [
          "myapp"
          "myapp_test"
        ];
      };

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "PostgreSQL port. If null, uses computed port from stackpanel.ports.";
      };

      package = lib.mkOption {
        type = lib.types.package;
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
        description = "Minio package to use";
      };
    };

    caddy = {
      enable = lib.mkEnableOption "Global Caddy reverse proxy";

      sites = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Sites to register with Caddy (domain -> upstream)";
        example = {
          "myapp.localhost" = "localhost:3000";
          "api.localhost" = "localhost:8080";
        };
      };
    };
  };

  # Set package defaults when pkgs is available
  config = lib.mkIf hasPkgs {
    stackpanel.globalServices = {
      postgres.package = lib.mkDefault pkgs.postgresql_17;
      redis.package = lib.mkDefault pkgs.redis;
      minio.package = lib.mkDefault pkgs.minio;
    };
  };
}
