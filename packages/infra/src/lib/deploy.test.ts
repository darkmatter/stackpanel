import { describe, expect, test } from "bun:test";
import { AlchemyContext } from "alchemy/AlchemyContext";
import { deployMissing, upgradeOutdated } from "alchemy/State/Provisioning";
import type { StateStoreError } from "alchemy/State";
import type { ConfigError } from "effect/Config";
import * as ConfigProvider from "effect/ConfigProvider";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Result from "effect/Result";
import { useExistingStateStore, usesLocalAlchemyState } from "./deploy";

describe("usesLocalAlchemyState", () => {
  test("uses filesystem state only for the local dev stage", () => {
    expect(usesLocalAlchemyState({ stage: "dev", appEnv: "dev" })).toBe(true);
  });

  test("uses shared state for PR previews and named non-production stages", () => {
    expect(usesLocalAlchemyState({ stage: "pr-42", appEnv: "dev" })).toBe(false);
    expect(usesLocalAlchemyState({ stage: "preview", appEnv: "dev" })).toBe(false);
  });

  test("uses shared state for staging and production", () => {
    expect(usesLocalAlchemyState({ stage: "staging", appEnv: "staging" })).toBe(false);
    expect(usesLocalAlchemyState({ stage: "production", appEnv: "prod" })).toBe(false);
  });
});

test("app plan approval cannot bootstrap or upgrade a shared store in CI", async () => {
  class Connection extends Context.Service<
    Connection,
    Effect.Effect<number, StateStoreError | ConfigError>
  >()("test/DeferredStateConnection") {}
  const store = { backend: "cloudflare", label: "fixture" };
  let mutations = 0;
  const provision = Effect.sync(() => ++mutations);
  const cli = { dotAlchemy: ".alchemy", dev: false, adopt: true, updateStateStore: true };
  const cases = [
    ["connected", Effect.succeed(8)],
    ["bootstrap", deployMissing(store, provision)],
    ["upgrade", upgradeOutdated({ ...store, observed: 7, expected: 8 }, provision)],
  ] as const;

  for (const [expected, open] of cases) {
    // The provider captures the layer context now and opens the store later.
    const state = Layer.effect(
      Connection,
      Effect.map(Effect.context<never>(), (ctx) => open.pipe(Effect.provideContext(ctx))),
    ).pipe(useExistingStateStore);
    const result = await Effect.runPromise(
      Effect.gen(function* () {
        expect((yield* AlchemyContext).updateStateStore).toBe(true);
        return yield* Effect.result(yield* Connection);
      }).pipe(
        Effect.provide(state),
        Effect.provideService(AlchemyContext, cli),
        Effect.provide(ConfigProvider.layer(ConfigProvider.fromUnknown({ CI: true }))),
      ),
    );
    if (expected === "connected") {
      expect(Result.isSuccess(result) && result.success).toBe(8);
    } else {
      expect(
        Result.isFailure(result) && "requires" in result.failure && result.failure.requires?.action,
      ).toBe(expected);
    }
  }
  expect(mutations).toBe(0);
});
