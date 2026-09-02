import {
  loadDeployEnv,
  resolveDeployStage,
  selectStateBackend,
} from "@stackpanel/infra/lib/deploy";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Effect from "effect/Effect";

const PROJECT = "stackpanel";
const SERVICE = "docs";

// `appEnv` is our SOPS namespace (`prod` | `staging` | `dev`); the raw `stage`
// remains visible via alchemy's `Stage` service inside the program. Both are
// derived from one source so the secrets we decrypt match the deploy target.
const deployStage = resolveDeployStage();
const { appEnv } = deployStage;

// Decrypts the per-app SOPS payload and injects it into process.env so the
// Cloudflare provider can read CLOUDFLARE_* credentials without `sops
// exec-env`. Hard-fails with a copy-pasteable message listing every missing
// required env var.
await loadDeployEnv(SERVICE, appEnv);

// Custom hostname per stage:
//   production => docs.stackpanel.com
//   staging    => docs.staging.stackpanel.com
//   PR / other => workers.dev (zone wildcard is `*.stackpanel.com`, so
//                 `docs.pr-N.stackpanel.com` is not covered; Alchemy's
//                 workers.dev URL is the reliable preview target)
const hostnameFor = (stage: string): string | undefined => {
  if (stage === "production") return "docs.stackpanel.com";
  if (stage === "staging") return "docs.staging.stackpanel.com";
  return undefined;
};

const program = Effect.gen(function* () {
  const stage = yield* Alchemy.Stage;
  const hostname = hostnameFor(stage);
  const incrementalCache = yield* Cloudflare.R2.Bucket("DocsIncrementalCache", {
    name: `${PROJECT}-${SERVICE}-${stage}-incremental-cache`,
  });

  // Website.Nextjs runs the wrangler-free OpenNext pipeline from
  // `@distilled.cloud/nextjs` (esbuild + code-splitting final pass) so
  // OpenNext's runtime dynamic imports stay intact — no pre-bundle step.
  const website = yield* Cloudflare.Website.Nextjs("Docs", {
    // Stable physical name prevents orphaned workers when Alchemy's
    // per-deploy InstanceId changes (e.g. state loss between CI runs).
    name: `stackpanel-docs-${stage}`,
    memo: {
      include: [
        "src/**",
        "content/**",
        "public/**",
        "package.json",
        "next.config.mjs",
        "open-next.config.ts",
        "source.config.ts",
        "tsconfig.json",
        ".build-info",
      ],
    },
    // Zone is inferred from the hostname; omitted for local/dev/PR.
    ...(hostname !== undefined ? { domain: hostname } : {}),
    env: {
      NEXT_INC_CACHE_R2_BUCKET: incrementalCache,
      NEXT_INC_CACHE_R2_PREFIX: `${stage}/incremental-cache`,
    },
    compatibility: {
      // Website.Nextjs defaults to 2026-05-12; keep explicit so node:perf_hooks
      // (required by OpenNext/Next edge) stays available.
      date: "2026-05-12",
      flags: [
        "nodejs_compat",
        "nodejs_compat_populate_process_env",
        "global_fetch_strictly_public",
      ],
    },
  });

  return { url: website.url };
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
