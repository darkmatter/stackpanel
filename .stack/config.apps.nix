{ config, ... }:
let
  # Shared across all web deployment environments
  shared = {
    vars = {
      BETTER_AUTH_SECRET = "";
      BETTER_AUTH_URL = "";
      CORS_ORIGIN = "";
      POLAR_ACCESS_TOKEN = "";
      POLAR_SUCCESS_URL = "";
      POSTGRES_URL = "/dev/postgres-url";
      CLOUDFLARE_ACCOUNT_ID = "/shared/cloudflare-account-id";
      CLOUDFLARE_API_TOKEN = "/shared/cloudflare-api-token";
      AWS_SANDBOX_ACCESS_KEY_ID = "/shared/aws-sandbox-access-key-id";
      AWS_SANDBOX_SECRET_ACCESS_KEY = "/shared/aws-sandbox-secret-access-key";
      CLOUDFLARE_SERVICE_ACCOUNT_CLIENT_ID = "/shared/cloudflare-service-account-client-id";
      CLOUDFLARE_SERVICE_ACCOUNT_CLIENT_SECRET = "/shared/cloudflare-service-account-client-secret";
      HETZNER_API_KEY = "/shared/hetzner-api-key";
    };
    secrets = [
      "BETTER_AUTH_SECRET"
      "POLAR_ACCESS_TOKEN"
      "POSTGRES_URL"
      "CLOUDFLARE_ACCOUNT_ID"
      "CLOUDFLARE_API_TOKEN"
      "AWS_SANDBOX_ACCESS_KEY_ID"
      "AWS_SANDBOX_SECRET_ACCESS_KEY"
      "CLOUDFLARE_SERVICE_ACCOUNT_CLIENT_ID"
      "CLOUDFLARE_SERVICE_ACCOUNT_CLIENT_SECRET"
      "HETZNER_API_KEY"
    ];
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

    environmentVariables = {
      PORT = {
        key = "PORT";
        secret = false;
        defaultValue = "3001";
      };
    };

    deployment = {
      enable = false;
      backend = "alchemy";
      host = "cloudflare";
      targets = [ "ovh-usw-1" ];
      command = "bun serve.ts";
      cloudflare.workerName = "stackpanel-docs";
      modules = [
        { networking.firewall.allowedTCPPorts = [ 3001 ]; }
      ];
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

    environmentVariables = {
      STACKPANEL_TEST_PAIRING_TOKEN = {
        key = "STACKPANEL_TEST_PAIRING_TOKEN";
        secret = false;
        defaultValue = "token123";
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

    environmentVariables = {
      PORT = {
        key = "PORT";
        secret = false;
        defaultValue = "3000";
      };
      HOSTNAME = {
        key = "HOSTNAME";
        secret = false;
        defaultValue = "stackpanel.lan";
      };
    } // builtins.mapAttrs (name: value: {
      key = name;
      secret = builtins.elem name shared.secrets;
      defaultValue = value;
    }) shared.vars;

    deployment = {
      # Bindings and secrets are auto-derived from environments.
      # Override only when deploy-time names differ from dev names.
      enable = false;
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
