// packages/infra/src/docs.stack.ts
import { Stack, Build, Cloudflare } from "alchemy-effect";
import * as Output from "alchemy-effect/Output";
import * as Effect from "effect/Effect";
import * as Path from "effect/Path";

// 1. Build the OpenNext worker as a Build.Command resource
const DocsBuild = Effect.gen(function* () {
  const pathModule = yield* Path.Path;

  // Resolve apps/web from here in a stable way; Path.resolve works on both node/bun.
  const docsDir = pathModule.resolve("../../apps/docs");

  const build = yield* Build.Command("docs-build", {
    command: "bun run build",        // or "pnpm build", etc.
    cwd: docsDir,                     // run inside apps/docs
    hash: [
      "app/**",
      "pages/**",
      "src/**",
      "public/**",
      "content/**",
      "package.json",
      "bun.lockb",
      "next.config.*",
      "open-next.config.*",
      "wrangler.jsonc",
    ],
    outdir: ".open-next",           // relative to cwd
    env: {
      NODE_ENV: "production",
      // anything OpenNext needs at build-time
    },
  });

  return build; // { outdir: string; hash: string }
});

// 2. Use the build output to define the Worker
const DocsWorker = Effect.gen(function* () {
  const pathModule = yield* Path.Path;
  const build = yield* DocsBuild;

  const workerBundle = yield* Output.map(build.outdir, (outdir) =>
    pathModule.join(outdir, "worker.js"),
  );

  const worker = yield* Cloudflare.Worker("DocsWorker", {
    main: workerBundle,
  });

  return { worker } as const;
});

// 3. Stack that wires it all together
export default Stack.make(
  "DocsStack",
  Cloudflare.providers(),
)(
  Effect.gen(function* () {
    const { worker } = yield* DocsWorker;

    return {
      workerId: worker.workerId,
      url: worker.url,
    } as const;
  }),
);
