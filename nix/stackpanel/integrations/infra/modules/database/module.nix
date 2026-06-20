# ==============================================================================
# infra/modules/database/module.nix
#
# Database Infrastructure Module
#
# Provisions database resources based on environment:
#   - Production/CI: Neon Postgres (serverless, branching for preview envs)
#   - Local (docker): Docker Postgres container (fallback)
#
# The module detects the runtime environment via env vars and provisions
# the appropriate backend. Outputs a DATABASE_URL that other modules
# and apps can consume.
#
# Usage in .stack/config.nix:
#   stackpanel.infra.database = {
#     enable = true;
#     name = "my-project";
#     provider = "auto";  # or "neon", "docker"
#     neon = {
#       region = "aws-us-east-1";
#       pg-version = 16;
#       api-key-ssm-path = "/common/neon-api-key";
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
      example = true;
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = defaultDbName;
      description = "Database name (used for Neon project name, Postgres DB name, etc.)";
      example = "my_project";
    };

    provider = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "neon"
        "docker"
      ];
      default = "auto";
      description = ''
        Database provider.

        - auto: Detect environment at runtime. Uses Docker if USE_DOCKER=true,
          otherwise Neon.
        - neon: Always use Neon Postgres (requires API key in SSM).
        - docker: Always use Docker Postgres container.
      '';
      example = "neon";
    };

    # --------------------------------------------------------------------------
    # Neon configuration
    # --------------------------------------------------------------------------
    neon = {
      region = lib.mkOption {
        type = lib.types.str;
        default = "aws-us-east-1";
        description = "Neon region ID";
        example = "aws-us-east-1";
      };

      pg-version = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "PostgreSQL version for Neon project";
        example = 16;
      };

      api-key-ssm-path = lib.mkOption {
        type = lib.types.str;
        default = "/common/neon-api-key";
        description = "SSM parameter path for the Neon API key";
        example = "/common/neon-api-key";
      };

      enable-branching = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable Neon branching for preview environments.
          When a non-prod/dev stage is detected, creates a separate Neon branch.
        '';
        example = true;
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
        example = "postgres";
      };

      tag = lib.mkOption {
        type = lib.types.str;
        default = "16-alpine";
        description = "Docker image tag";
        example = "16-alpine";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = projectName;
        description = "Postgres user for Docker container";
        example = "my-project";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = projectName;
        description = "Postgres password for Docker container";
        example = "my-project";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 5432;
        description = "Host port mapping for Docker Postgres";
        example = 5432;
      };

      network = lib.mkOption {
        type = lib.types.str;
        default = "${projectName}_network";
        description = "Docker network name";
        example = "my-project_network";
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
        example = true;
      };

      path-prefix = lib.mkOption {
        type = lib.types.str;
        default = "/${projectName}";
        description = "SSM path prefix (stage is appended: /<prefix>/<stage>/database-url)";
        example = "/my-project";
      };
    };
  };

  # ============================================================================
  # Config: register in infra module system
  # ============================================================================
  config = lib.mkIf (infraCfg.enable && cfg.enable) {
    stackpanel.infra.modules.database = {
      name = "Database";
      description = "Postgres database provisioning (Neon / Docker)";
      path = ./index.ts;
      inputs = {
        inherit projectName;
        inherit (cfg) name provider;
        neon = {
          inherit (cfg.neon) region enable-branching;
          pgVersion = cfg.neon.pg-version;
          apiKeySsmPath = cfg.neon.api-key-ssm-path;
        };
        docker = {
          inherit (cfg.docker)
            image
            tag
            user
            password
            port
            network
            ;
        };
        ssm = {
          inherit (cfg.ssm) enable;
          pathPrefix = cfg.ssm.path-prefix;
        };
      };
      dependencies = {
        "alchemy" = config.stackpanel.deployment.alchemy.version;
      }
      // lib.optionalAttrs config.stackpanel.deployment.alchemy.enable {
        ${config.stackpanel.deployment.alchemy.package.name} = "workspace:*";
      };
      outputs = {
        databaseUrl = {
          description = "PostgreSQL connection URL";
          sensitive = true;
          sync = true;
        };
        provider = {
          description = "Active database provider (neon, docker)";
          sync = true;
        };
      };
    };
  };
}
