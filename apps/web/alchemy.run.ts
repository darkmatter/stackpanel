import {
  loadDeployEnv,
  resolveDeployStage,
  selectStateBackend,
} from "@stackpanel/infra/lib/deploy";
import { NeonProject, neonProviders } from "@stackpanel/infra/resources/neon";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

const PROJECT = "stackpanel";
const SERVICE = "web";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); `stage` is what
// alchemy itself sees and mirrors into `Stage`. Both are derived from a single
// source of truth so the secrets we decrypt match the resources we provision.
const deployStage = resolveDeployStage();
const { appEnv } = deployStage;

// Decrypts the per-app SOPS payload (CLOUDFLARE_*, NEON_API_KEY, …) and injects
// it into process.env so downstream Cloudflare/Neon providers see it. Hard-fails
// with a copy-pasteable message listing every missing required env var.
await loadDeployEnv(SERVICE, appEnv);

const program = Effect.gen(function* () {
  const stage = yield* Alchemy.Stage;
  const label = stage.replaceAll("_", "-");
  const appBaseUrl =
    stage === "production"
      ? "https://stackpanel.com"
      : stage === "dev"
        ? "http://localhost:3001"
        : `https://${label}.stackpanel.com`;
  const db = yield* NeonProject("postgres", {
    name: `${PROJECT}-${stage}`,
    regionId: "aws-us-east-1",
    pgVersion: 17,
    databaseName: `${SERVICE}_${stage}`,
    roleName: `${PROJECT}-${SERVICE}-owner`,
  });

  // Where the worker's `/docs/*` proxy (apps/web/src/routes/docs/$.ts,
  // index.ts) forwards requests. Mirrors `hostnameFor` in
  // apps/docs/alchemy.run.ts so each stage proxies to its own docs
  // deployment; PR previews and dev fall back to the production docs site
  // since we don't deploy a per-PR docs Worker. Without this binding the
  // route handler returns 503 ("DOCS_PROXY_URL environment variable is not
  // configured") for every /docs link on the marketing page.
  const docsProxyUrl =
    stage === "production"
      ? "https://docs.stackpanel.com"
      : stage === "staging"
        ? "https://docs.staging.stackpanel.com"
        : "https://docs.stackpanel.com";

  // Production binds two hostnames to the same worker:
  //   - apex stackpanel.com → marketing/landing (`/`, `/login`, …)
  //   - local.stackpanel.com → studio (mirrors local.drizzle.studio: the
  //     `/studio/*` routes talk to the user's machine via
  //     http://127.0.0.1:9876).
  // Both ship the same bundle today; auth cookies are scoped to
  // `.stackpanel.com` so a session from the apex carries into the studio.
  // Preview/staging use `${stage}.stackpanel.com`, which the zone
  // wildcard `*.stackpanel.com` covers. Nested `local.${stage}.…`
  // hostnames are not.
  const domain =
    stage === "dev"
      ? undefined
      : stage === "production"
        ? {
          name: "local.stackpanel.com",
          aliases: ["stackpanel.com"],
        }
        : `${label}.stackpanel.com`;

  // Forward the runtime secrets we just decrypted via `loadDeployEnv` into
  // the Cloudflare Worker's environment. These are ALREADY decrypted at
  // deploy time (the `loadDeployEnv("web", appEnv)` call above pulls the
  // per-app SOPS payload + the deploy scope into `process.env` of the
  // deploy process). Forwarding them here makes Cloudflare store each as a
  // Worker secret on the deployed script, so every Worker isolate boots
  // with `process.env.BETTER_AUTH_SECRET` already populated — no per-
  // isolate SOPS decrypt cost on the cold path.
  //
  // Polar values default to `""` so a missing-secret deploy still boots:
  // consumer code treats empty as "feature disabled" (`polarClient` stays
  // null, webhook plugin not mounted).
  //
  // See `docs/adr/0003-build-time-env-injection-with-effect-config.md`
  // (which supersedes the runtime-decrypt approach in ADR 0001).
  const website = yield* Cloudflare.Website.Vite("TanstackStart", {
    // Stable physical name prevents orphaned workers when Alchemy's
    // per-deploy InstanceId changes (e.g. state loss between CI runs).
    name: `stackpanel-web-${stage}`,
    ...(domain !== undefined ? { domain } : {}),
    compatibility: {
      flags: ["nodejs_compat"],
    },
    env: {
      DATABASE_URL: db.connectionUri,
      BETTER_AUTH_SECRET: process.env.BETTER_AUTH_SECRET ?? "",
      BETTER_AUTH_URL: process.env.BETTER_AUTH_URL ?? appBaseUrl,
      CORS_ORIGIN: process.env.CORS_ORIGIN ?? appBaseUrl,
      STACKPANEL_DEPLOY_ENV: stage,
      POLAR_ACCESS_TOKEN: process.env.POLAR_ACCESS_TOKEN ?? "",
      POLAR_WEBHOOK_SECRET: process.env.POLAR_WEBHOOK_SECRET ?? "",
      POLAR_SUCCESS_URL:
        process.env.POLAR_SUCCESS_URL ?? `${appBaseUrl}/dashboard/billing`,
      POLAR_PRO_PRODUCT_ID_PRODUCTION:
        process.env.POLAR_PRO_PRODUCT_ID_PRODUCTION ?? "",
      POLAR_FREE_PRODUCT_ID_PRODUCTION:
        process.env.POLAR_FREE_PRODUCT_ID_PRODUCTION ?? "",
      DOCS_PROXY_URL: docsProxyUrl,
    },
  });

  return {
    url: website.url,
    databaseUrl: db.connectionUri,
  };
});

const providers = Layer.mergeAll(
  Cloudflare.providers(),
  neonProviders(),
) as Layer.Layer<any, never, any>;

export default Alchemy.Stack(
  `${PROJECT}-${SERVICE}`,
  {
    providers,
    // Local dev uses filesystem state; CI previews/staging/prod use the shared
    // Cloudflare-hosted state store so destroy jobs see current resource IDs.
    state: selectStateBackend(deployStage),
  },
  program,
);
