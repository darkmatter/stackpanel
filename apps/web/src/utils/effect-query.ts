// src/utils/effect-query.ts
import { useQuery } from "@tanstack/react-query";
import { createEffectQuery } from "effect-query";
import { Context, Effect, Layer, ManagedRuntime } from "effect";

export class GreetingApi extends Context.Service<
  GreetingApi,
  {
    readonly loadGreeting: () => Effect.Effect<string>;
  }
>()("example/GreetingApi") { }

const GreetingApiLive = Layer.succeed(GreetingApi)({
  loadGreeting: () => Effect.succeed("Hello, world!"),
});

export const eq = createEffectQuery(GreetingApiLive);

// Alternative: Create from effect-query from ManagedRuntime instead of Layer
import { createEffectQueryFromManagedRuntime } from "effect-query";

const runtime = ManagedRuntime.make(GreetingApiLive);
export const eqFromRuntime = createEffectQueryFromManagedRuntime(runtime);