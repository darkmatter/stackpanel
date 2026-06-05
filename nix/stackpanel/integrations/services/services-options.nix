# ==============================================================================
# services.nix
#
# Development services configuration - the canonical service type system.
#
# Defines `stackpanel.services` (attrsOf submodule) and `stackpanel.serviceModules`
# (listOf deferredModule), mirroring the apps + appModules pattern.
#
# Services are long-running processes (databases, caches, object stores, etc.)
# that are managed by process-compose under the "services" namespace.
#
# Each service definition provides:
#   - A foreground start command (with built-in init-if-needed logic)
#   - Port, environment variables, packages for the devshell
#   - Process-compose integration (readiness probes, restart policies, etc.)
#     injected via serviceModules by the process-compose module
#
# The `stackpanel.globalServices` convenience layer maps into this system
# for backward compatibility.
#
# Usage:
#   # Direct style (new):
#   stackpanel.services.postgres = {
#     enable = true;
#     displayName = "PostgreSQL";
#     command = "${postgresStartScript}/bin/postgres-start";
#     port = 5432;
#     autoStart = true;
#     env = { DATABASE_URL = "..."; };
#     packages = [ pkgs.postgresql_17 ];
#   };
#
#   # Or via globalServices (backward-compatible):
#   stackpanel.globalServices = {
#     enable = true;
#     postgres.enable = true;
#   };
#
# Extension:
#   # Other modules can inject per-service options via serviceModules:
#   stackpanel.serviceModules = [{
#     options.myFeature = lib.mkOption { ... };
#   }];
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  ...
}:
let
  cfg = config.stackpanel;

  # ---------------------------------------------------------------------------
  # Base service submodule - defines the core shape of every service
  # ---------------------------------------------------------------------------
  serviceBaseModule =
    { name, lib, ... }:
    {
      options = {
        enable = lib.mkEnableOption "this service";

        displayName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Human-readable display name for the service.";
          example = "PostgreSQL";
        };

        description = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Short description of the service.";
          example = "Relational database for application data";
        };

        command = lib.mkOption {
          type = lib.types.str;
          description = ''
            Command to start the service in foreground mode.
            This should be an idempotent script that initializes data
            directories if needed, then exec's the service binary.
            Process-compose manages the lifecycle (restart, shutdown).
          '';
          example = lib.literalExpression ''"''${postgresStartScript}/bin/postgres-start"'';
        };

        port = lib.mkOption {
          type = lib.types.nullOr lib.types.port;
          default = null;
          description = ''
            Primary port for this service. Optional - some services
            (like file watchers) don't use ports.
          '';
          example = 5432;
        };

        autoStart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to auto-start this service when `dev` is run.
            If false, the service is visible in the process-compose TUI
            but must be started manually.
          '';
        };

        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Environment variables contributed by this service to the devshell.
            These are available to all processes and the interactive shell.
          '';
          example = lib.literalExpression ''
            {
              DATABASE_URL = "postgresql://localhost:5432/mydb";
              PGHOST = "/tmp/postgres";
            }
          '';
        };

        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = ''
            Packages added to the devshell PATH when this service is enabled.
            Typically includes the service binary and CLI tools (psql, redis-cli, etc.).
          '';
        };

        shellHook = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Shell hook code run during devshell initialization.
            Used for environment setup that can't be expressed as static env vars.
          '';
        };

        dataDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Path where this service stores its data.
            Typically under .stack/state/services/<name>/.
          '';
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Compute enabled services and aggregate their contributions
  # ---------------------------------------------------------------------------
  enabledServices = lib.filterAttrs (_: s: s.enable) cfg.services;
  enabledServicesList = lib.attrValues enabledServices;

in
{
  # ===========================================================================
  # Options
  # ===========================================================================

  options.stackpanel.serviceModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Additional modules to extend service configuration options.

      This allows other modules (like process-compose) to inject per-service
      options into every service definition. Works identically to appModules.

      Example: The process-compose module injects process-compose.namespace,
      process-compose.readiness_probe, etc. into every service.
    '';
  };

  options.stackpanel.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [
          serviceBaseModule
        ] ++ config.stackpanel.serviceModules;
        specialArgs = { inherit lib; };
      }
    );
    default = { };
    description = ''
      Development services managed by process-compose.

      Each service is a long-running process (database, cache, object store, etc.)
      that gets a process-compose entry under the "services" namespace.

      Services can be defined directly here or via the stackpanel.globalServices
      convenience layer (which maps into this option internally).

      The process-compose module injects additional per-service options
      (namespace, readiness_probe, availability, depends_on) via serviceModules.
    '';
    example = lib.literalExpression ''
      {
        postgres = {
          enable = true;
          displayName = "PostgreSQL";
          command = "''${postgresStartScript}/bin/postgres-start";
          port = 5432;
          autoStart = true;
          env = {
            DATABASE_URL = "postgresql://localhost:5432/mydb";
          };
          packages = [ pkgs.postgresql_17 ];
        };
        redis = {
          enable = true;
          displayName = "Redis";
          command = "''${redisStartScript}/bin/redis-start";
          port = 6379;
        };
      }
    '';
  };

  # ===========================================================================
  # Config - aggregate service contributions into devshell
  # ===========================================================================
  config = lib.mkIf (enabledServices != { }) {
    # Merge all enabled services' packages into devshell
    stackpanel.devshell.packages = lib.concatMap (s: s.packages) enabledServicesList;

    # Merge all enabled services' env vars into devshell
    stackpanel.devshell.env = lib.mergeAttrsList (map (s: s.env) enabledServicesList);

    # Merge all enabled services' shell hooks into devshell
    stackpanel.devshell.hooks.main = lib.filter (h: h != "") (
      map (s: s.shellHook) enabledServicesList
    );

    # Contribute computed variables for each service's port
    stackpanel.variables = lib.mkMerge (
      lib.mapAttrsToList (
        name: svc:
        lib.optionalAttrs (svc.port != null) {
          "/computed/services/${name}/port" = {
            value = toString svc.port;
          };
        }
      ) enabledServices
    );
  };
}
