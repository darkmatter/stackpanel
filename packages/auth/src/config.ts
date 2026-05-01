// Typed, redacted access to the env vars `@stackpanel/auth` consumes.
//
// Secrets travel through SOPS at *deploy* time:
//
//   1. `apps/web/alchemy.run.ts` calls `loadDeployEnv("web", appEnv)` —
//      decrypts the per-app + deploy SOPS payload into the deploy
//      process's `process.env`.
//   2. The same script forwards the resulting values into
//      `Cloudflare.Vite({ env: { ... } })`.
//   3. Cloudflare stores those values as Worker secrets on the deployed
//      script. Every Worker isolate boots with `process.env.BETTER_AUTH_SECRET`
//      already populated — no per-isolate SOPS decrypt cost on the cold
//      path.
//
// At read time (here), `effect/Config` resolves against the default
// `ConfigProvider` (`ConfigProvider.fromEnv()`), which reads `process.env`.
// Secrets are wrapped in `Redacted<string>` so accidental logging /
// JSON.stringify doesn't leak them; unwrap with `Redacted.value` only at
// the boundary where the underlying SDK requires a raw string.
//
// See `docs/adr/0003-build-time-env-injection-with-effect-config.md`.

import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Option from "effect/Option";
import * as Redacted from "effect/Redacted";

const program = Effect.gen(function* () {
  const betterAuthSecret = yield* Config.option(
    Config.redacted("BETTER_AUTH_SECRET"),
  );
  const polarAccessToken = yield* Config.option(
    Config.redacted("POLAR_ACCESS_TOKEN"),
  );
  const polarWebhookSecret = yield* Config.option(
    Config.redacted("POLAR_WEBHOOK_SECRET"),
  );
  const polarSuccessUrl = yield* Config.option(
    Config.string("POLAR_SUCCESS_URL"),
  );
  const corsOrigin = yield* Config.option(Config.string("CORS_ORIGIN"));
  const stackpanelDeployEnv = yield* Config.option(
    Config.string("STACKPANEL_DEPLOY_ENV"),
  );
  return {
    betterAuthSecret,
    polarAccessToken,
    polarWebhookSecret,
    polarSuccessUrl,
    corsOrigin,
    stackpanelDeployEnv,
  };
});

// Materialize once at module load. `Effect.runSync` here is safe because
// `ConfigProvider.fromEnv()` is synchronous (no I/O) and `Config.option`
// converts missing-data errors into `Option.none()` — so the only way this
// throws is a true validation failure (none of these schemas have one).
const resolved = Effect.runSync(program);

/** Better-Auth signing secret — `Redacted` so it doesn't accidentally leak. */
export const betterAuthSecret: Option.Option<Redacted.Redacted<string>> =
  resolved.betterAuthSecret;

/** Polar API access token. When `None`, the polar plugin is not mounted. */
export const polarAccessToken: Option.Option<Redacted.Redacted<string>> =
  resolved.polarAccessToken;

/** Polar webhook signing secret. When `None`, the webhooks plugin is not mounted. */
export const polarWebhookSecret: Option.Option<Redacted.Redacted<string>> =
  resolved.polarWebhookSecret;

/** Optional Polar success-redirect URL. */
export const polarSuccessUrl: Option.Option<string> = resolved.polarSuccessUrl;

/** Trusted CORS origin for Better-Auth. */
export const corsOrigin: Option.Option<string> = resolved.corsOrigin;

/**
 * Resolved deploy environment marker (`"production"` | `"preview"` |
 * `"dev"`). Used to decide cookie scoping behaviour. Read as a plain
 * `Option<string>` because the value is not sensitive.
 */
export const stackpanelDeployEnv: Option.Option<string> =
  resolved.stackpanelDeployEnv;

/**
 * Unwrap a `Redacted<string>` only at the boundary where an SDK requires
 * a raw string. Centralized so callers don't sprinkle `Redacted.value`
 * around the codebase.
 */
export const reveal = Redacted.value;

/**
 * Treats an empty string the same as a missing value. Used because
 * `Cloudflare.Vite({ env: { POLAR_ACCESS_TOKEN: process.env.POLAR_ACCESS_TOKEN ?? "" } })`
 * forwards literal `""` for an unset secret rather than dropping the key,
 * and downstream code expects "" to mean "feature disabled".
 */
export function presentString(opt: Option.Option<string>): string | undefined {
  return Option.match(opt, {
    onNone: () => undefined,
    onSome: (s) => (s === "" ? undefined : s),
  });
}

/** Same shape as {@link presentString} but for `Redacted<string>`. */
export function presentRedacted(
  opt: Option.Option<Redacted.Redacted<string>>,
): string | undefined {
  return Option.match(opt, {
    onNone: () => undefined,
    onSome: (r) => {
      const v = Redacted.value(r);
      return v === "" ? undefined : v;
    },
  });
}
