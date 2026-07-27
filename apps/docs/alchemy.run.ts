import {
  loadDeployEnv,
  resolveDeployStage,
  selectStateBackend,
} from "@stackpanel/infra/lib/deploy";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Output from "alchemy/Output";
import * as Workers from "@distilled.cloud/cloudflare/workers";
import * as Effect from "effect/Effect";
import * as Schedule from "effect/Schedule";

const PROJECT = "stackpanel";
const SERVICE = "docs";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); the raw `stage`
// remains visible via alchemy's `Stage` service inside the program. Both are
// derived from one source so the secrets we decrypt match the deploy target.
const deployStage = resolveDeployStage();
const { appEnv } = deployStage;

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
  const stage = yield* Alchemy.Stage;
  const incrementalCache = yield* Cloudflare.R2Bucket("DocsIncrementalCache", {
    name: `${PROJECT}-${SERVICE}-${stage}-incremental-cache`,
  });

  // OpenNext-on-Cloudflare emits the worker entrypoint and assets directory.
  // The build is expected to have already run (`bun run build:worker`); this
  // resource only handles upload + binding wiring.
  const website = yield* Cloudflare.Worker("Docs", {
    // Stable physical name prevents orphaned workers when Alchemy's
    // per-deploy InstanceId changes (e.g. state loss between CI runs).
    name: `stackpanel-docs-${stage}`,
    // `.open-next/worker.js` is OpenNext's tiny ~2KB entrypoint — it expects to
    // be passed through a wrangler-style bundler that resolves the relative
    // `./cloudflare/*.js` imports and inlines them. Two viable bundlers:
    //
    //   1. wrangler (esbuild under the hood) — bundles statics, *preserves*
    //      runtime `import()` paths. This is what `opennextjs-cloudflare deploy`
    //      uses internally and what OpenNext is designed against.
    //   2. alchemy's built-in cloudflareRolldown — also bundles statics, but
    //      mangles OpenNext's dynamic `import("./server-functions/default/
    //      handler.mjs")` so its `resolveWrapper(...)` returns `undefined` at
    //      request time. The deployed Worker then throws
    //        `TypeError: Cannot destructure property 'name' of '(intermediate
    //         value)'`
    //      inside `createGenericHandler` and every dynamic Next route
    //      (`/docs/*`, …) returns 500. Static routes (`/`, `/api/search`)
    //      survive because they're served by the ASSETS binding without
    //      entering the broken handler.
    //
    // We pre-bundle with wrangler in `bun run build:worker`
    // (`wrangler deploy --dry-run --outdir=.open-next/dist`) and point
    // `main:` at the resulting self-contained file, then tell alchemy to skip
    // its own bundling pass with `bundle: false` so the byte-for-byte upload
    // is the wrangler artifact.
    main: ".open-next/dist/worker.js",
    // OpenNext emits a plain Workers default export `{ fetch }` — the alchemy
    // bootstrap that wraps `main` in `Layer.effect(tag, entry)` mis-handles
    // that shape and the deployed worker throws CF 1101 on first request.
    // `isExternal: true` skips the wrapper so the bundle keeps OpenNext's own
    // entrypoint.
    isExternal: true,
    // The `bundle: false` opt-out is added by patches/alchemy@2.0.0-beta.43.patch
    // (a backport of the proposed upstream change at
    //  https://github.com/alchemy-run/alchemy-effect — the
    //  `feat(cloudflare/Worker): add bundle: false …` commit). It short-
    // circuits `prepareBundle` to upload `props.main` byte-for-byte. Drop the
    // patch + this prop once cloudflareRolldown's dynamic-import handling is
    // fixed upstream and we can bundle through alchemy directly.
    bundle: false,
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
    bindings: {
      NEXT_INC_CACHE_R2_BUCKET: incrementalCache,
    },
    env: {
      NEXT_INC_CACHE_R2_PREFIX: `${stage}/incremental-cache`,
    },
    compatibility: {
      // Must be >= 2026-03-17 — that's the date Cloudflare started providing
      // node:perf_hooks as a native module. OpenNext (via Next.js's edge
      // runtime) imports it transitively, and on earlier dates the unenv
      // polyfill itself references node:perf_hooks, so the worker throws
      // `No such module "node:perf_hooks"` on first request (CF error 1101).
      date: "2026-03-17",
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
            // Cloudflare transiently 404s workers-domain DELETEs right
            // after the worker upload (binding record rebuild) — retry
            // through that window instead of dying on a phantom 404.
            yield* Workers.deleteDomain({ accountId, domainId: d.id! }).pipe(
              Effect.retry({
                while: (e) => e._tag === "CloudflareHttpError",
                schedule: Schedule.spaced("2 seconds"),
                times: 5,
              }),
            );
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

export default Alchemy.Stack(
  `${PROJECT}-${SERVICE}`,
  {
    providers: Cloudflare.providers(),
    // Local dev uses filesystem state; CI previews/staging/prod use the shared
    // Cloudflare-hosted state store so destroy jobs see current resource IDs.
    state: selectStateBackend(deployStage),
  },
  program,
);
