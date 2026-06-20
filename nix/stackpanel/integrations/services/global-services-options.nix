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
  pkgs ? null,
  ...
}:
let
  # pkgs is optional - provided by devenv/flakeModule via _module.args
  # or passed directly in specialArgs
  hasPkgs = pkgs != null;

  cfg = config.stackpanel.globalServices;
in
{
  options.stackpanel.globalServices = {
    enable = lib.mkEnableOption ''
      global singleton development services shared by all projects on this machine.

      Enable this when a workspace should use Stackpanel-managed PostgreSQL,
      Redis, Minio, or Caddy instead of each project starting its own copies.
    '';

    project-name = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        Project slug used as the default database name and as the owner label
        for Caddy site registration.

        Keep this stable across machines so generated database names, service
        env vars, and local vhosts are predictable for the team.
      '';
      example = "stackpanel";
    };

    postgres = {
      enable = lib.mkEnableOption ''
        global PostgreSQL service for app and test databases.
      '';

      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ cfg.project-name ];
        description = ''
          PostgreSQL databases to create when the global service starts.

          Include one database per app or runtime boundary, plus explicit test
          databases when test suites should not share development data.
        '';
        example = [
          "web"
          "api"
          "api_test"
        ];
      };

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          PostgreSQL TCP port. If null, Stackpanel uses the deterministic port
          computed for this project, avoiding hardcoded team-local ports.
        '';
        example = 5432;
      };

      package = lib.mkOption {
        type = lib.types.package;
        description = "PostgreSQL package to install and run for the global service.";
        example = lib.literalExpression "pkgs.postgresql_17";
      };
    };

    redis = {
      enable = lib.mkEnableOption ''
        global Redis service for cache, queue, session, or rate-limit state.
      '';

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          Redis TCP port. If null, Stackpanel uses the deterministic Redis port
          for this workspace.
        '';
        example = 6379;
      };

      package = lib.mkOption {
        type = lib.types.package;
        description = "Redis package to install and run for the global service.";
        example = lib.literalExpression "pkgs.redis";
      };
    };

    minio = {
      enable = lib.mkEnableOption ''
        global Minio S3-compatible object storage for local buckets.
      '';

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          Minio S3 API port. If null, Stackpanel uses the deterministic Minio
          API port for this workspace.
        '';
        example = 9000;
      };

      console-port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          Minio web console port. If null, Stackpanel uses the deterministic
          Minio console port for this workspace.
        '';
        example = 9001;
      };

      package = lib.mkOption {
        type = lib.types.package;
        description = "Minio package to install and run for local S3-compatible storage.";
        example = lib.literalExpression "pkgs.minio";
      };
    };

    caddy = {
      enable = lib.mkEnableOption ''
        global Caddy reverse proxy for local app domains.
      '';

      sites = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Static Caddy site registrations, keyed by local domain and valued by
          upstream address.

          Use this for services that are not already declared as Stackpanel apps,
          such as admin consoles, webhook receivers, or external dev servers.
        '';
        example = {
          "web.stackpanel.localhost" = "localhost:3000";
          "api.stackpanel.localhost" = "localhost:8080";
          "minio.stackpanel.localhost" = "localhost:9001";
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
