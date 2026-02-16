# ==============================================================================
# infra/modules/cache/module.nix
#
# Cache Infrastructure Module
#
# Provisions cache/Redis resources based on environment:
#   - Production/CI: Upstash Redis (serverless, REST API)
#   - Local (devenv): Devenv-managed Redis (read-only reference)
#   - Local (docker): Docker Valkey/Redis container (fallback)
#
# Usage in .stackpanel/config.nix:
#   stackpanel.infra.cache = {
#     enable = true;
#     provider = "auto";
#     upstash = {
#       region = "us-east-1";
#       api-key-ssm-path = "/common/upstash-api-key";
#       email-ssm-path = "/common/upstash-email";
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.cache;
  projectName = config.stackpanel.name or "my-project";
  infraCfg = config.stackpanel.infra;
in
{
  # ============================================================================
  # Options
  # ============================================================================
  options.stackpanel.infra.cache = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable cache infrastructure provisioning";
    };

    provider = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "upstash"
        "devenv"
        "docker"
      ];
      default = "auto";
      description = ''
        Cache provider.

        - auto: Detect environment at runtime. Uses devenv if IN_NIX_SHELL is set,
          docker if USE_DOCKER=true, otherwise Upstash.
        - upstash: Always use Upstash Redis.
        - devenv: Always reference devenv-managed Redis.
        - docker: Always use Docker Valkey container.
      '';
    };

    # --------------------------------------------------------------------------
    # Upstash configuration
    # --------------------------------------------------------------------------
    upstash = {
      region = lib.mkOption {
        type = lib.types.str;
        default = "us-east-1";
        description = "Upstash Redis region";
      };

      api-key-ssm-path = lib.mkOption {
        type = lib.types.str;
        default = "/common/upstash-api-key";
        description = "SSM parameter path for the Upstash API key";
      };

      email-ssm-path = lib.mkOption {
        type = lib.types.str;
        default = "/common/upstash-email";
        description = "SSM parameter path for the Upstash account email";
      };
    };

    # --------------------------------------------------------------------------
    # Devenv configuration
    # --------------------------------------------------------------------------
    devenv = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Redis host in devenv";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 6379;
        description = "Redis port in devenv";
      };
    };

    # --------------------------------------------------------------------------
    # Docker configuration
    # --------------------------------------------------------------------------
    docker = {
      image = lib.mkOption {
        type = lib.types.str;
        default = "valkey/valkey";
        description = "Docker image for Redis/Valkey";
      };

      tag = lib.mkOption {
        type = lib.types.str;
        default = "latest";
        description = "Docker image tag";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 6379;
        description = "Host port mapping for Docker Redis";
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
        description = "Write Redis URL and token to SSM Parameter Store";
      };

      path-prefix = lib.mkOption {
        type = lib.types.str;
        default = "/${projectName}";
        description = "SSM path prefix (stage is appended)";
      };
    };
  };

  # ============================================================================
  # Config: register in infra module system
  # ============================================================================
  config = lib.mkIf (infraCfg.enable && cfg.enable) {
    stackpanel.infra.modules.cache = {
      name = "Cache";
      description = "Redis/Valkey cache provisioning (Upstash / devenv / Docker)";
      path = ./index.ts;
      inputs = {
        inherit projectName;
        inherit (cfg) provider;
        upstash = {
          inherit (cfg.upstash) region;
          apiKeySsmPath = cfg.upstash.api-key-ssm-path;
          emailSsmPath = cfg.upstash.email-ssm-path;
        };
        devenv = {
          inherit (cfg.devenv) host port;
        };
        docker = {
          inherit (cfg.docker) image tag port network;
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
        redisUrl = {
          description = "Redis connection URL (endpoint)";
          sync = true;
        };
        redisToken = {
          description = "Redis REST token (Upstash only)";
          sensitive = true;
          sync = true;
        };
        provider = {
          description = "Active cache provider (upstash, devenv, docker)";
          sync = true;
        };
      };
    };
  };
}
