# ==============================================================================
# infra/modules/database/module.nix
#
# Database Infrastructure Module
#
# Provisions database resources based on environment:
#   - Production/CI: Neon Postgres (serverless, branching for preview envs)
#   - Local (devenv): Devenv-managed Postgres (read-only reference)
#   - Local (docker): Docker Postgres container (fallback)
#
# The module detects the runtime environment via env vars and provisions
# the appropriate backend. Outputs a DATABASE_URL that other modules
# and apps can consume.
#
# Usage in .stackpanel/config.nix:
#   stackpanel.infra.database = {
#     enable = true;
#     name = "my-project";
#     provider = "auto";  # or "neon", "devenv", "docker"
#     neon = {
#       region = "aws-us-east-1";
#       pg-version = 16;
#       api-key-ssm-path = "/common/neon-api-key";
#     };
#     devenv = {
#       database = "my-project";
#       user = "pguser";
#       password = "password";
#       port = 5432;
#     };
#     docker = {
#       image = "postgres";
#       tag = "16-alpine";
#       port = 5432;
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.database;
  projectName = config.stackpanel.name or "my-project";
  infraCfg = config.stackpanel.infra;

  # Default database name based on project
  defaultDbName = builtins.replaceStrings [ "-" ] [ "_" ] projectName;
in
{
  # ============================================================================
  # Options
  # ============================================================================
  options.stackpanel.infra.database = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable database infrastructure provisioning";
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = defaultDbName;
      description = "Database name (used for Neon project name, Postgres DB name, etc.)";
    };

    provider = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "neon"
        "devenv"
        "docker"
      ];
      default = "auto";
      description = ''
        Database provider.

        - auto: Detect environment at runtime. Uses devenv if IN_NIX_SHELL is set,
          docker if USE_DOCKER=true, otherwise Neon.
        - neon: Always use Neon Postgres (requires API key in SSM).
        - devenv: Always reference devenv-managed Postgres.
        - docker: Always use Docker Postgres container.
      '';
    };

    # --------------------------------------------------------------------------
    # Neon configuration
    # --------------------------------------------------------------------------
    neon = {
      region = lib.mkOption {
        type = lib.types.str;
        default = "aws-us-east-1";
        description = "Neon region ID";
      };

      pg-version = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "PostgreSQL version for Neon project";
      };

      api-key-ssm-path = lib.mkOption {
        type = lib.types.str;
        default = "/common/neon-api-key";
        description = "SSM parameter path for the Neon API key";
      };

      enable-branching = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable Neon branching for preview environments.
          When a non-prod/dev stage is detected, creates a separate Neon branch.
        '';
      };
    };

    # --------------------------------------------------------------------------
    # Devenv configuration (local development)
    # --------------------------------------------------------------------------
    devenv = {
      database = lib.mkOption {
        type = lib.types.str;
        default = defaultDbName;
        description = "Postgres database name in devenv";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "pguser";
        description = "Postgres username in devenv";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = "password";
        description = "Postgres password in devenv";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Postgres host in devenv";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 5432;
        description = "Postgres port in devenv";
      };
    };

    # --------------------------------------------------------------------------
    # Docker configuration (fallback local development)
    # --------------------------------------------------------------------------
    docker = {
      image = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        description = "Docker image for Postgres";
      };

      tag = lib.mkOption {
        type = lib.types.str;
        default = "16-alpine";
        description = "Docker image tag";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = projectName;
        description = "Postgres user for Docker container";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = projectName;
        description = "Postgres password for Docker container";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 5432;
        description = "Host port mapping for Docker Postgres";
      };

      network = lib.mkOption {
        type = lib.types.str;
        default = "${projectName}_network";
        description = "Docker network name";
      };
    };

    # --------------------------------------------------------------------------
    # Output configuration
    # --------------------------------------------------------------------------
    ssm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Write DATABASE_URL to SSM Parameter Store after provisioning";
      };

      path-prefix = lib.mkOption {
        type = lib.types.str;
        default = "/${projectName}";
        description = "SSM path prefix (stage is appended: /<prefix>/<stage>/database-url)";
      };
    };
  };

  # ============================================================================
  # Config: register in infra module system
  # ============================================================================
  config = lib.mkIf (infraCfg.enable && cfg.enable) {
    stackpanel.infra.modules.database = {
      name = "Database";
      description = "Postgres database provisioning (Neon / devenv / Docker)";
      path = ./index.ts;
      inputs = {
        inherit projectName;
        inherit (cfg) name provider;
        neon = {
          inherit (cfg.neon) region enable-branching;
          pgVersion = cfg.neon.pg-version;
          apiKeySsmPath = cfg.neon.api-key-ssm-path;
        };
        devenv = {
          inherit (cfg.devenv) database user password host port;
        };
        docker = {
          inherit (cfg.docker) image tag user password port network;
        };
        ssm = {
          inherit (cfg.ssm) enable;
          pathPrefix = cfg.ssm.path-prefix;
        };
      };
      dependencies = {
        "alchemy" = "catalog:";
      }
      // lib.optionalAttrs (config.stackpanel.alchemy.enable) {
        ${config.stackpanel.alchemy.package.name} = "workspace:*";
      };
      outputs = {
        databaseUrl = {
          description = "PostgreSQL connection URL";
          sensitive = true;
          sync = true;
        };
        provider = {
          description = "Active database provider (neon, devenv, docker)";
          sync = true;
        };
      };
    };
  };
}
