import { loadDeployEnv, resolveDeployStage } from "@stackpanel/infra/lib/deploy";
import { Cloudflare, Output, Stage } from "alchemy-effect";
import * as Stack from "alchemy-effect/Stack";
import * as Workers from "@distilled.cloud/cloudflare/workers";
import * as Effect from "effect/Effect";

const PROJECT = "stackpanel";
const SERVICE = "docs";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); the raw `stage`
// remains visible via alchemy's `Stage` service inside the program. Both are
// derived from one source so the secrets we decrypt match the deploy target.
const { appEnv } = resolveDeployStage();

// Decrypts the per-app SOPS payload and injects it into process.env so
// `wrangler`/opennext and the Cloudflare provider can read CLOUDFLARE_*
// credentials without `sops exec-env`. Hard-fails with a copy-pasteable
// message listing every missing required env var.
await loadDeployEnv(SERVICE, appEnv);

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
    // OpenNext emits a plain Workers default export `{ fetch }` — the alchemy
    // bootstrap that wraps `main` in `Layer.effect(tag, entry)` mis-handles
    // that shape and the deployed worker throws CF 1101 on first request.
    // `isExternal: true` skips the wrapper so the bundle keeps OpenNext's own
    // entrypoint.
    isExternal: true,
    // Mirror apps/docs/wrangler.jsonc — OpenNext serves its own routing so the
    // worker must run for missed asset paths, and we want the SPA-style
    // trailing-slash handling for static MDX routes.
    assets: {
      directory: ".open-next/assets",
      config: {
        notFoundHandling: "none",
        htmlHandling: "auto-trailing-slash",
        runWorkerFirst: false,
      },
    },
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

  return { url };
});

export default Stack.make(`${PROJECT}-${SERVICE}`, Cloudflare.providers())(program);
