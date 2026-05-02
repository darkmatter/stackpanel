import {
  loadDeployEnv,
  resolveDeployStage,
  selectStateBackend,
} from "@stackpanel/infra/lib/deploy";
import { NeonProject, neonProviders } from "@stackpanel/infra/resources/neon";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Output from "alchemy/Output";
import * as Workers from "@distilled.cloud/cloudflare/workers";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

const PROJECT = "stackpanel";
const SERVICE = "web";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); `stage` is what
// alchemy itself sees and mirrors into `Stage`. Both are derived from a single
// source of truth so the secrets we decrypt match the resources we provision.
const { appEnv } = resolveDeployStage();

// Decrypts the per-app SOPS payload (CLOUDFLARE_*, NEON_API_KEY, …) and injects
// it into process.env so downstream Cloudflare/Neon providers see it. Hard-fails
// with a copy-pasteable message listing every missing required env var.
await loadDeployEnv(SERVICE, appEnv);

// stackpanel.com
const STACKPANEL_ZONE = "d34628a3ab639230ff1f6dc1eb640eec";

const program = Effect.gen(function* () {
  const stage = yield* Alchemy.Stage;
  const label = stage.replaceAll("_", "-");
  const db = yield* NeonProject("postgres", {
    name: `${PROJECT}-${stage}`,
    regionId: "aws-us-east-1",
    pgVersion: 17,
    databaseName: `${SERVICE}_${stage}`,
    roleName: `${PROJECT}-${SERVICE}-owner`,
  });

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
  const website = yield* Cloudflare.Vite("TanstackStart", {
    compatibility: {
      flags: ["nodejs_compat"],
    },
    env: {
      DATABASE_URL: db.connectionUri,
      BETTER_AUTH_SECRET: process.env.BETTER_AUTH_SECRET ?? "",
      POLAR_ACCESS_TOKEN: process.env.POLAR_ACCESS_TOKEN ?? "",
      POLAR_WEBHOOK_SECRET: process.env.POLAR_WEBHOOK_SECRET ?? "",
      POLAR_PRO_PRODUCT_ID_PRODUCTION:
        process.env.POLAR_PRO_PRODUCT_ID_PRODUCTION ?? "",
      POLAR_FREE_PRODUCT_ID_PRODUCTION:
        process.env.POLAR_FREE_PRODUCT_ID_PRODUCTION ?? "",
    },
  });
  let url: Output.Output<string | undefined> = website.url;

  if (stage !== "dev") {
    // Production binds two hostnames to the same worker:
    //   - apex stackpanel.com → marketing/landing (`/`, `/login`, …)
    //   - local.stackpanel.com → studio (mirrors local.drizzle.studio: the
    //     `/studio/*` routes talk to the user's machine via
    //     http://127.0.0.1:9876).
    // Both ship the same bundle today; auth cookies are scoped to
    // `.stackpanel.com` so a session from the apex carries into the studio.
    // Non-prod stages only get the studio hostname — there's no marketing
    // preview to host on the apex.
    const hostnames =
      stage === "production"
        ? ["local.stackpanel.com", "stackpanel.com"]
        : [`local.${label}.stackpanel.com`];
    const primary = hostnames[0]!;
    url = Output.all(website.accountId, website.workerName).pipe(
      Output.mapEffect(([accountId, workerName]) =>
        Effect.gen(function* () {
          for (const hostname of hostnames) {
            const existing = yield* Workers.listDomains({
              accountId,
              hostname,
            });
            const stale = existing.result.filter(
              (d) => d.hostname === hostname && d.id,
            );
            if (stale.length > 0) {
              yield* Effect.log(
                `[alchemy] purging ${stale.length} existing binding(s) at ${hostname}: ${stale
                  .map((d) => `${d.service ?? "?"}#${d.id}`)
                  .join(", ")}`,
              );
            }
            for (const d of stale) {
              yield* Workers.deleteDomain({ accountId, domainId: d.id! });
            }
            yield* Workers.putDomain({
              accountId,
              hostname,
              service: workerName,
              zoneId: STACKPANEL_ZONE,
            });
          }
          return `https://${primary}` as string | undefined;
        }).pipe(Effect.orDie),
      ),
    );
  }

  return {
    url,
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
    // dev/PR previews → filesystem state (cached across CI runs);
    // staging/prod → shared Cloudflare-hosted state store.
    state: selectStateBackend(appEnv),
  },
  program,
);
