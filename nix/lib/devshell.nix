# Global Development Services for `nix develop`
#
# This library provides the same global singleton services as the devenv module,
# but compatible with standard `nix develop` (flake devShells / mkShell).
#
# Usage in flake.nix:
#
#   {
#     inputs.stackpanel.url = "github:darkmatter/stackpanel";
#     inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
#
#     outputs = { self, nixpkgs, stackpanel, ... }:
#       let
#         system = "x86_64-linux";
#         pkgs = nixpkgs.legacyPackages.${system};
#         devServices = stackpanel.lib.mkDevShell pkgs {
#           projectName = "myproject";
#           postgres = {
#             enable = true;
#             databases = ["myapp" "myapp_test"];
#           };
#           redis.enable = true;
#           minio.enable = true;
#           caddy.enable = true;
#         };
#       in {
#         devShells.${system}.default = pkgs.mkShell (devServices // {
#           # Add your own packages
#           packages = devServices.packages ++ [ pkgs.nodejs ];
#         });
#       };
#   }
#
# Or merge with an existing mkShell:
#
#   devShells.default = pkgs.mkShell {
#     packages = [ pkgs.nodejs ] ++ devServices.packages;
#     shellHook = ''
#       ${devServices.shellHook}
#       echo "My custom setup"
#     '';
#   } // { inherit (devServices) env; };
#
{
  pkgs,
  lib ? pkgs.lib,
}: let
  # Import the modular services library
  servicesLib = import ./services {inherit pkgs lib;};
  caddyLib = import ./caddy.nix {inherit pkgs lib;};

  # Default configuration - services can be added by including them here
  defaultConfig = {
    projectName = "default";

    # Each service follows the pattern:
    # serviceName = {
    #   enable = false;
    #   ...options specific to that service
    # };
    postgres = {
      enable = false;
      databases = null; # Will default to [projectName] if null
      port = 5432;
      package = pkgs.postgresql_17;
    };

    redis = {
      enable = false;
      port = 6379;
      package = pkgs.redis;
    };

    minio = {
      enable = false;
      port = 9000;
      consolePort = 9001;
      package = pkgs.minio;
    };

    caddy = {
      enable = false;
      sites = {};
      # Step CA integration (optional)
      stepEnabled = false;
      stepCaUrl = "";
      stepCaFingerprint = "";
    };
  };

  # Deep merge helper
  mergeConfig = defaults: user:
    lib.recursiveUpdate defaults user;
in {
  # Main entry point: creates shell attributes for mkShell
  mkDevShell = userConfig: let
    cfg = mergeConfig defaultConfig userConfig;

    # Resolve databases default
    databases =
      if cfg.postgres.databases == null
      then [cfg.projectName]
      else cfg.postgres.databases;

    # Create service instances
    postgres = lib.optionalAttrs cfg.postgres.enable (servicesLib.mkGlobalPostgres {
      projectName = cfg.projectName;
      databases = databases;
      port = cfg.postgres.port;
      package = cfg.postgres.package;
    });

    redis = lib.optionalAttrs cfg.redis.enable (servicesLib.mkGlobalRedis {
      projectName = cfg.projectName;
      port = cfg.redis.port;
      package = cfg.redis.package;
    });

    minio = lib.optionalAttrs cfg.minio.enable (servicesLib.mkGlobalMinio {
      projectName = cfg.projectName;
      port = cfg.minio.port;
      consolePort = cfg.minio.consolePort;
      package = cfg.minio.package;
    });

    caddyScripts = lib.optionalAttrs cfg.caddy.enable (caddyLib.mkCaddyScripts {
      stepEnabled = cfg.caddy.stepEnabled;
      stepCaUrl = cfg.caddy.stepCaUrl;
      stepCaFingerprint = cfg.caddy.stepCaFingerprint;
    });

    # Controller for unified management
    controller = servicesLib.mkDevServicesController {
      projectName = cfg.projectName;
      postgres =
        if cfg.postgres.enable
        then postgres
        else null;
      redis =
        if cfg.redis.enable
        then redis
        else null;
      minio =
        if cfg.minio.enable
        then minio
        else null;
      caddy =
        if cfg.caddy.enable
        then caddyScripts
        else null;
    };

    # Collect all packages
    packages =
      (lib.optionals cfg.postgres.enable postgres.allPackages)
      ++ (lib.optionals cfg.redis.enable redis.allPackages)
      ++ (lib.optionals cfg.minio.enable minio.allPackages)
      ++ (lib.optionals cfg.caddy.enable caddyScripts.allPackages)
      ++ controller.allPackages;

    # Build shell hook for service configuration
    shellHook = lib.concatStringsSep "\n" ([
        "# Stackpanel global services initialization"
      ]
      ++ lib.optional cfg.postgres.enable postgres.shellHook
      ++ lib.optional cfg.redis.enable redis.shellHook
      ++ lib.optional cfg.minio.enable minio.shellHook
      ++ lib.optional (cfg.caddy.enable && cfg.caddy.sites != {}) ''
        # Register this project's Caddy sites
        ${lib.concatMapStringsSep "\n" (site: ''
          ${caddyScripts.caddyAddSite}/bin/caddy-add-site "${site}" "${cfg.caddy.sites.${site}}" 2>/dev/null || true
        '') (lib.attrNames cfg.caddy.sites)}
      ''
      ++ [
        ""
        "# Run 'stackpanel --help' to see available commands"
      ]);

    # Environment variables
    env = lib.mergeAttrsList [
      (lib.optionalAttrs cfg.postgres.enable {
        PGHOST = "$HOME/.local/share/devservices/postgres/socket";
        PGPORT = toString cfg.postgres.port;
        DATABASE_URL = "postgresql://localhost:${toString cfg.postgres.port}/${lib.head databases}";
      })
      (lib.optionalAttrs cfg.redis.enable {
        REDIS_URL = "redis://localhost:${toString cfg.redis.port}";
      })
      (lib.optionalAttrs cfg.minio.enable {
        # NOTE: Do NOT set AWS_ENDPOINT_URL_S3 globally - it breaks AWS IAM auth.
        # Use MINIO_ENDPOINT or S3_ENDPOINT for apps that need Minio.
        MINIO_ENDPOINT = "http://localhost:${toString cfg.minio.port}";
        S3_ENDPOINT = "http://localhost:${toString cfg.minio.port}";
        MINIO_ROOT_USER = "minioadmin";
        MINIO_ROOT_PASSWORD = "minioadmin";
      })
    ];
  in {
    inherit packages shellHook;

    # For mkShell, environment variables should be passed directly
    # This can be spread into mkShell or used with passthru
    inherit env;

    # Individual service configs for advanced use
    services = {
      inherit postgres redis minio;
      caddy = caddyScripts;
      inherit controller;
    };

    # Helper to create a complete mkShell
    # Usage: stackpanel.lib.mkDevShell pkgs { ... }.shell
    shell = pkgs.mkShell ({
        inherit packages shellHook;
      }
      // env);
  };
}
