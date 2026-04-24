import { loadDeployEnv, resolveDeployStage } from "@stackpanel/infra/lib/deploy";
import { Cloudflare } from "alchemy-effect";
import * as Stack from "alchemy-effect/Stack";
import * as Effect from "effect/Effect";

const PROJECT = "stackpanel";
const SERVICE = "api";

const { appEnv } = resolveDeployStage();
await loadDeployEnv(SERVICE, appEnv);

const program = Effect.gen(function* () {
  const worker = yield* Cloudflare.Worker("ApiWorker", {
    // Prebuilt by `bun run build` — a single ESM bundle with every
    // dep (standardwebhooks, aws4fetch, drizzle-orm, Polar SDK, …)
    // rolled in. alchemy-effect's default loader leaves transitive
    // imports unresolved on the Worker runtime; bundling locally
    // sidesteps that.
    main: "./.output/server/index.mjs",
    compatibility: {
      flags: ["nodejs_compat"],
    },
  });

  return { url: worker.url };
});

export default Stack.make(
  `${PROJECT}-${SERVICE}`,
  Cloudflare.providers(),
)(program);
