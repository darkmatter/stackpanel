import * as Cloudflare from "alchemy-effect/Cloudflare";
import * as Stack from "alchemy-effect/Stack";
import * as Effect from "effect/Effect";

// Shared infrastructure stack.
// App-specific deployment lives in apps/{web,docs}/alchemy.run.ts.

export default Stack.make(
  "stackpanel-infra",
  Cloudflare.providers(),
)(
  Effect.gen(function* () {
    // Shared infra resources (OIDC, KMS, etc.) can be added here.
    // App deployment is handled by each app's own alchemy.run.ts:
    //   - apps/web/alchemy.run.ts   (Neon + Cloudflare Vite + domain binding)
    //   - apps/docs/alchemy.run.ts  (Cloudflare Nextjs)
    return {};
  }),
);
