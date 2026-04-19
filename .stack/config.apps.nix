{ config, lib, ... }:
let
  # Shared across all web deployment environments
  envs = {
    shared = {
      BETTER_AUTH_SECRET = { };
      BETTER_AUTH_URL = { };
      CORS_ORIGIN = { };
      POLAR_ACCESS_TOKEN = { };
      POLAR_SUCCESS_URL = { };
      POSTGRES_URL = {
        sops = "/dev/postgres-url";
      };
      CLOUDFLARE_ACCOUNT_ID = {
        sops = "/shared/cloudflare-account-id";
      };
      CLOUDFLARE_API_TOKEN = {
        sops = "/shared/cloudflare-api-token";
      };
      AWS_SANDBOX_ACCESS_KEY_ID = {
        sops = "/shared/aws-sandbox-access-key-id";
      };
      AWS_SANDBOX_SECRET_ACCESS_KEY = {
        sops = "/shared/aws-sandbox-secret-access-key";
      };
      CLOUDFLARE_SERVICE_ACCOUNT_CLIENT_ID = {
        sops = "/shared/cloudflare-service-account-client-id";
      };
      CLOUDFLARE_SERVICE_ACCOUNT_CLIENT_SECRET = {
        sops = "/shared/cloudflare-service-account-client-secret";
      };
      HETZNER_API_KEY = {
        sops = "/shared/hetzner-api-key";
      };
    };
  };
in
{
  # apps/docs
  docs = {
    name = "docs";
    description = "Documentation site";
    path = "apps/docs";
    type = "bun";
    domain = "docs";
    tls = true;

    bun.generateFiles = false;
    framework.nextjs.enable = true;
    linting.oxlint.enable = true;

    env = {
      PORT = {
        value = "3001";
      };
    }
    // envs.shared;

    deployment = {
      # Bindings and secrets are auto-derived from environments.
      # Override only when deploy-time names differ from dev names.
      enable = true;
      backend = "alchemy";
      host = "cloudflare";
      cloudflare.workerName = "stackpanel-docs";
    };
  };

  # apps/stackpanel-go
  stackpanel-go = {
    name = "stackpanel";
    description = "Stackpanel CLI and agent (Go)";
    path = "apps/stackpanel-go";
    type = "go";

    go = {
      enable = true;
      binaryName = "stackpanel";
      generateFiles = false;
      ldflags = [
        "-s"
        "-w"
      ];
    };

    env = {
      STACKPANEL_TEST_PAIRING_TOKEN = {
        value = "token123";
      };
    };
  };

  # apps/web
  web = {
    name = "web";
    description = "Main web application";
    path = "apps/web";
    type = "bun";
    domain = "@";
    tls = true;

    bun = {
      enable = true;
      buildPhase = "./node_modules/.bin/vite build";
      startScript = "node .output/server/index.mjs";
      generateFiles = false;
    };

    framework.tanstack-start.enable = true;

    linting.oxlint = {
      enable = true;
      fix = true;
      categories = {
        correctness = "error";
        suspicious = "warn";
      };
      plugins = [
        "react"
        "typescript"
      ];
    };

    container = {
      enable = true;
      type = "bun";
    };

    env = {
      PORT = {
        value = "3000";
      };
      HOSTNAME = {
        value = "stackpanel.lan";
      };
    }
    // envs.shared;

    deployment = {
      # Bindings and secrets are auto-derived from environments.
      # Override only when deploy-time names differ from dev names.
      enable = true;
      host = "cloudflare";
      aws = {
        region = "us-west-2";
        os-type = "nixos";
      };
      cloudflare.workerName = "stackpanel-web";
      fly = {
        appName = "stackpanel-web";
        region = "iad";
      };
    };
  };
}
