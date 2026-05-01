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
      # Secrets — sourced from `.stack/secrets/vars/shared.sops.yaml` so the
      # codegen embeds real ciphertext into each app's per-env runtime payload
      # (`packages/gen/env/data/<env>/<app>.sops.json`). At deploy time
      # `loadDeployEnv` decrypts the deploy scope into `process.env`, then
      # `apps/web/alchemy.run.ts` forwards these values into
      # `Cloudflare.Vite({ env })` so Cloudflare stores them as Worker
      # secrets and Workers boot with `process.env.BETTER_AUTH_SECRET`
      # already populated. See `docs/adr/0003-build-time-env-injection-with-effect-config.md`.
      #
      # Same secrets are *also* declared in the `deploy` root env scope
      # (`.stack/config.nix:envs.deploy`) so deploy-time tooling (alchemy
      # bindings, `apps/api/scripts/push-secrets.sh`) can read them — that
      # remains; the two scopes serve different consumers.
      BETTER_AUTH_SECRET = {
        required = true;
        sops = "/shared/better-auth-secret";
        description = "Better Auth signing secret. Generate with `openssl rand -hex 32`.";
      };
      POLAR_ACCESS_TOKEN = {
        required = false;
        sops = "/shared/polar-access-token";
        description = "Polar.sh API access token used for billing. When unset, polarClient is null and billing endpoints no-op.";
      };
      POLAR_WEBHOOK_SECRET = {
        required = false;
        sops = "/shared/polar-webhook-secret";
        description = "Polar.sh webhook signing secret. When unset, the polar webhooks plugin is not mounted.";
      };
      POLAR_PRO_PRODUCT_ID_PRODUCTION = {
        required = false;
        sops = "/shared/polar-pro-product-id-production";
        description = "Polar product ID for the Pro plan in production. Falls back to the sandbox product when unset.";
      };
      POLAR_FREE_PRODUCT_ID_PRODUCTION = {
        required = false;
        sops = "/shared/polar-free-product-id-production";
        description = "Polar product ID for the Free plan in production. Falls back to the sandbox product when unset.";
      };

      # Per-environment URL/CORS config — not secrets, so no SOPS source.
      # Left as `required = false` because the consuming code handles missing
      # values gracefully (better-auth derives BETTER_AUTH_URL from the
      # request host; CORS_ORIGIN/POLAR_SUCCESS_URL fall back to upstream
      # defaults). Wire per-env literals via
      # `stackpanel.envs."apps/<app>/<env>".KEY = { value = "..."; };`
      # in `.stack/config.nix` if you need explicit values.
      BETTER_AUTH_URL = {
        required = false;
        description = "Public URL the auth server is reachable at (used for OAuth redirects).";
      };
      CORS_ORIGIN = {
        required = false;
        description = "Comma-separated allowed origins for the API.";
      };
      POLAR_SUCCESS_URL = {
        required = false;
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
  # apps/api
  api = {
    name = "api";
    description = "Cloud API (Better-Auth, Polar webhooks, hosted alchemy state).";
    path = "apps/api";
    type = "bun";

    bun.generateFiles = false;

    env = {
      PORT = {
        value = "3000";
      };
    }
    // envs.shared;

    container = {
      enable = true;
      type = "bun";
      port = 3000;
    };

    deployment = {
      enable = true;
      host = "fly";
      fly = {
        appName = "stackpanel-api";
        region = "iad";
        memory = "512mb";
        cpus = 1;
        autoStop = "stop";
        minMachines = 1;
        forceHttps = true;
      };
    };
  };

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
