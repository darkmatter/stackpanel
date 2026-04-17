// import { Stage } from "alchemy-effect";
import * as Console from "effect/Console";
import * as Cloudflare from "alchemy-effect/Cloudflare";
import { web } from "@gen/env";
// import * as GitHub from "alchemy-effect/GitHub";
// import * as Stack from "alchemy-effect/Stack";
// import * as Effect from "effect/Effect";
// import Worker from "./src/worker.ts";
import * as Stack from "alchemy-effect/Stack";
import * as Effect from "effect/Effect";
import Worker from "./src/worker";
import { fromApiToken } from "@distilled.cloud/cloudflare";

export const cloudflareCredentials = fromApiToken({
  apiToken: web.env.CLOUDFLARE_API_TOKEN,
})

Console.log(cloudflareCredentials);



export default Stack.make(
  "WebStack",
  Cloudflare.providers(),
)(
  Effect.gen(function* () {
    // const stage = yield* Stage;

    const worker = yield* Worker;

    // if (stage.startsWith("pr-")) {
    //   yield* GitHub.Comment("Preview")`Preview deployed to ${worker.url}`;
    // }

    return {
      url: worker.url,
    };
  }),
)