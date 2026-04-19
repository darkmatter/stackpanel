import { loadAppEnv } from "@gen/env/runtime";
import { Cloudflare, Output, Stage } from "alchemy-effect";
import * as Stack from "alchemy-effect/Stack";
import * as Workers from "@distilled.cloud/cloudflare/workers";
import * as Effect from "effect/Effect";

// Map alchemy --stage / $STAGE onto our SOPS env namespaces:
//   production -> prod, staging -> staging, anything else (pr-*, dev, ...) -> dev.
// Allow APP_ENV to override explicitly for one-off runs.
const STAGE = process.env.STAGE || process.env.ALCHEMY_STAGE || "dev";
const APP_ENV =
  process.env.APP_ENV ||
  (STAGE === "production" ? "prod" : STAGE === "staging" ? "staging" : "dev");
const PROJECT = "stackpanel";
const SERVICE = "docs";

// Decrypts the per-app SOPS payload and injects it into process.env so the
// downstream Cloudflare provider (and `wrangler`/opennext build) can read
// CLOUDFLARE_* credentials without requiring the operator to wrap the command
// in `sops exec-env`.
const env = await loadAppEnv(SERVICE, APP_ENV, { inject: true });

if (!env.CLOUDFLARE_API_TOKEN) {
  throw new Error(`
!! Missing required environment variable: CLOUDFLARE_API_TOKEN !!
- Confirm /shared/cloudflare-api-token is set in .stack/secrets/vars/shared.sops.yaml
- Confirm @gen/env codegen has been run (devshell entry or 'stackpanel preflight run')
- Or export CLOUDFLARE_API_TOKEN directly to bypass the SOPS loader.`);
}

// stackpanel.com — same zone used by apps/web for the apex deployment.
const STACKPANEL_ZONE = "d34628a3ab639230ff1f6dc1eb640eec";

// Custom hostname per stage:
//   production => docs.stackpanel.com
//   staging    => docs.staging.stackpanel.com
//   <other>    => docs.<stage>.stackpanel.com
const hostnameFor = (stage: string): string =>
  stage === "production" ? "docs.stackpanel.com" : `docs.${stage}.stackpanel.com`;

const program = Effect.gen(function* () {
  const stage = yield* Stage;

  // OpenNext-on-Cloudflare emits the worker entrypoint and assets directory.
  // The build is expected to have already run (`bun run build:worker`); this
  // resource only handles upload + binding wiring.
  const website = yield* Cloudflare.Worker("Docs", {
    main: ".open-next/worker.js",
    assets: ".open-next/assets",
    compatibility: {
      flags: [
        "nodejs_compat",
        "nodejs_compat_populate_process_env",
        "global_fetch_strictly_public",
      ],
    },
  });

  let url: Output.Output<string | undefined> = website.url;

  if (stage !== "dev") {
    const hostname = hostnameFor(stage);
    url = Output.all(website.accountId, website.workerName).pipe(
      Output.mapEffect(([accountId, workerName]) =>
        Effect.gen(function* () {
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
          return `https://${hostname}` as string | undefined;
        }).pipe(Effect.orDie),
      ),
    );
  }
   console.log('deployed url', url);
  return { url };
});

export default Stack.make(`${PROJECT}-${SERVICE}`, Cloudflare.providers())(program);
