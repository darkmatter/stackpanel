import * as Cloudflare from "alchemy-effect/Cloudflare";
import { env } from "@gen/env/web";
import * as Stack from "alchemy-effect/Stack";
import * as Effect from "effect/Effect";
import Worker from "./src/worker";

export default Stack.make(
  "WebStack",
  Cloudflare.providers(),
)(
  Effect.gen(function* () {
    yield* Effect.log(`Deploying with CLOUDFLARE_ACCOUNT_ID=${env.CLOUDFLARE_ACCOUNT_ID ? "set" : "missing"}`);

    const worker = yield* Worker;

    return {
      url: worker.url,
    };
  }),
)