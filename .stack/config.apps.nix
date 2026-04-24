{ config, lib, ... }:
let
  # App-runtime environment variables shared across our web apps.
  #
  # Deploy-time secrets (Cloudflare, Neon, Alchemy state, ...) are NOT here:
  # they live in the `deploy` root env scope (`stackpanel.envs.deploy`),
  # contributed automatically by the deploy module based on each app's
  # `deployment.host` / `deployment.backend`. Loaded at deploy time via
  # `loadEnvScope("deploy")` in `packages/infra/src/lib/deploy.ts`.
  #
  # `required = true` makes `loadAppEnv(..., { validate: true })` (used by
  # `alchemy.run.ts`) hard-fail with an actionable, copy-pasteable message
  # when the variable is missing. `description` shows up in that error
  # message and in the studio Variables UI.
  envs = {
    shared = {
      BETTER_AUTH_SECRET = {
        description = "Better Auth signing secret. Generate with `openssl rand -hex 32`.";
      };
      BETTER_AUTH_URL = {
        description = "Public URL the auth server is reachable at (used for OAuth redirects).";
      };
      CORS_ORIGIN = {
        description = "Comma-separated allowed origins for the API.";
      };
      POLAR_ACCESS_TOKEN = {
        description = "Polar.sh API access token used for billing.";
      };
      POLAR_SUCCESS_URL = {
        description = "Redirect URL Polar sends customers to after a successful checkout.";
      };
      POSTGRES_URL = {
        sops = "/dev/postgres-url";
        description = "Postgres connection string. For deploy this is auto-bound from the NeonProject and does not need to be pre-set.";
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
      backend = "alchemy";
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
