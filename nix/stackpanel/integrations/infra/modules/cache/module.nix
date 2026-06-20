# ==============================================================================
# infra/modules/cache/module.nix
#
# Cache Infrastructure Module
#
# Provisions cache/Redis resources based on environment:
#   - Production/CI: Upstash Redis (serverless, REST API)
#   - Local (docker): Docker Valkey/Redis container (fallback)
#
# Usage in .stack/config.nix:
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
      example = true;
    };

    provider = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "upstash"
        "docker"
      ];
      default = "auto";
      description = ''
        Cache provider.

        - auto: Detect environment at runtime. Uses Docker if USE_DOCKER=true,
          otherwise Upstash.
        - upstash: Always use Upstash Redis.
        - docker: Always use Docker Valkey container.
      '';
      example = "upstash";
    };

    # --------------------------------------------------------------------------
    # Upstash configuration
    # --------------------------------------------------------------------------
    upstash = {
      region = lib.mkOption {
        type = lib.types.str;
        default = "us-east-1";
        description = "Upstash Redis region";
        example = "us-east-1";
      };

      api-key-ssm-path = lib.mkOption {
        type = lib.types.str;
        default = "/common/upstash-api-key";
        description = "SSM parameter path for the Upstash API key";
        example = "/common/upstash-api-key";
      };

      email-ssm-path = lib.mkOption {
        type = lib.types.str;
        default = "/common/upstash-email";
        description = "SSM parameter path for the Upstash account email";
        example = "/common/upstash-email";
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
        example = "valkey/valkey";
      };

      tag = lib.mkOption {
        type = lib.types.str;
        default = "latest";
        description = "Docker image tag";
        example = "8-alpine";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 6379;
        description = "Host port mapping for Docker Redis";
        example = 6379;
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
        description = "Write Redis URL and token to SSM Parameter Store";
        example = true;
      };

      path-prefix = lib.mkOption {
        type = lib.types.str;
        default = "/${projectName}";
        description = "SSM path prefix (stage is appended)";
        example = "/my-project";
      };
    };
  };

  # ============================================================================
  # Config: register in infra module system
  # ============================================================================
  config = lib.mkIf (infraCfg.enable && cfg.enable) {
    stackpanel.infra.modules.cache = {
      name = "Cache";
      description = "Redis/Valkey cache provisioning (Upstash / Docker)";
      path = ./index.ts;
      inputs = {
        inherit projectName;
        inherit (cfg) provider;
        upstash = {
          inherit (cfg.upstash) region;
          apiKeySsmPath = cfg.upstash.api-key-ssm-path;
          emailSsmPath = cfg.upstash.email-ssm-path;
        };
        docker = {
          inherit (cfg.docker)
            image
            tag
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
          description = "Active cache provider (upstash, docker)";
          sync = true;
        };
      };
    };
  };
}
