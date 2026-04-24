import { loadDeployEnv, resolveDeployStage } from "@stackpanel/infra/lib/deploy";
import { Cloudflare, Output, Stage } from "alchemy-effect";
import * as Stack from "alchemy-effect/Stack";
import * as Workers from "@distilled.cloud/cloudflare/workers";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

const PROJECT = "stackpanel";
const SERVICE = "api";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); `stage` is
// what alchemy itself sees. Both derived from one source of truth so the
// secrets we decrypt match the resources we provision.
const { appEnv } = resolveDeployStage();

// Decrypts per-app SOPS payload (BETTER_AUTH_*, POLAR_*, AWS_*, …) into
// process.env for the CF provider to read during deploy.
await loadDeployEnv(SERVICE, appEnv);

const STACKPANEL_ZONE = "d34628a3ab639230ff1f6dc1eb640eec";

const program = Effect.gen(function* () {
  const stage = yield* Stage;

  const worker = yield* Cloudflare.Worker("ApiWorker", {
    main: "./src/index.ts",
    compatibility: {
      flags: ["nodejs_compat"],
    },
    env: {
      BETTER_AUTH_URL: process.env.BETTER_AUTH_URL ?? "",
      BETTER_AUTH_SECRET: process.env.BETTER_AUTH_SECRET ?? "",
      DATABASE_URL: process.env.POSTGRES_URL ?? process.env.DATABASE_URL ?? "",
      AWS_ACCESS_KEY_ID: process.env.AWS_SANDBOX_ACCESS_KEY_ID ?? process.env.AWS_ACCESS_KEY_ID ?? "",
      AWS_SECRET_ACCESS_KEY: process.env.AWS_SANDBOX_SECRET_ACCESS_KEY ?? process.env.AWS_SECRET_ACCESS_KEY ?? "",
      AWS_REGION: process.env.AWS_REGION ?? "us-east-1",
      STACKPANEL_KMS_ALIAS: process.env.STACKPANEL_KMS_ALIAS ?? "alias/stackpanel-secrets",
      POLAR_ACCESS_TOKEN: process.env.POLAR_ACCESS_TOKEN ?? "",
      POLAR_WEBHOOK_SECRET: process.env.POLAR_WEBHOOK_SECRET ?? "",
      POLAR_SUCCESS_URL: process.env.POLAR_SUCCESS_URL ?? "https://local.stackpanel.com/checkout/success",
      POLAR_PRO_PRODUCT_ID_PRODUCTION: process.env.POLAR_PRO_PRODUCT_ID_PRODUCTION ?? "",
      POLAR_FREE_PRODUCT_ID_PRODUCTION: process.env.POLAR_FREE_PRODUCT_ID_PRODUCTION ?? "",
      CORS_ORIGIN: process.env.CORS_ORIGIN ?? "https://local.stackpanel.com",
      CORS_ALLOWED_ORIGINS:
        process.env.CORS_ALLOWED_ORIGINS
        ?? "https://local.stackpanel.com,https://stackpanel.com,https://studio.stackpanel.com",
    },
  });

  let url: Output.Output<string | undefined> = worker.url;

  if (stage !== "dev") {
    const hostname =
      stage === "production" ? "api.stackpanel.com" : `api-${stage}.stackpanel.com`;

    url = Output.all(worker.accountId, worker.workerName).pipe(
      Output.mapEffect(([accountId, workerName]) =>
        Effect.gen(function* () {
          const existing = yield* Workers.listDomains({ accountId, hostname });
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
          return `https://${hostname}` as string | undefined;
        }).pipe(Effect.orDie),
      ),
    );
  }

  return { url };
});

const providers = Layer.mergeAll(Cloudflare.providers()) as Layer.Layer<
  any,
  never,
  any
>;

export default Stack.make(`${PROJECT}-${SERVICE}`, providers)(program);
