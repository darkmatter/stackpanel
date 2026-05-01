# 0003 — Build-time env injection with `effect/Config` for typed redacted access

- **Status**: Accepted
- **Date**: 2026-05-01
- **Supersedes**: [ADR 0001](./0001-runtime-secrets-via-gen-env-loader.md)
- **Related**: [ADR 0002](./0002-runtime-startup-migrations.md)

## Context

[ADR 0001](./0001-runtime-secrets-via-gen-env-loader.md) chose to ship
SOPS ciphertext into the Cloudflare Worker bundle and decrypt it on
every isolate boot via `@gen/env/runtime/edge`. The appeal was a
single-source-of-truth pipeline: a secret declared in
`.stack/config.apps.nix` plus a `stackpanel codegen build` would land in
the embedded payload and become available on `process.env` after the
loader runs, with no `apps/*/alchemy.run.ts` edit required.

In review, the per-isolate decrypt cost we waved away in 0001 turned
out to be the deciding factor. Cloudflare spawns Worker isolates
aggressively (per region, per cold path, when memory pressure evicts a
warm isolate, etc.). Each new isolate paid:

- one AGE X25519 key-derivation against `SOPS_AGE_KEY`, and
- N ChaCha20-Poly1305 decrypts (one per encrypted SOPS field).

For a payload of ~5 secrets that's tens of milliseconds added to the
cold path of a non-trivial fraction of requests — and the cost grows
linearly with every new secret we add. The payload itself changes far
less often than a Worker isolate spins up; paying for the work on
every isolate boot is wrong-shaped.

The original instinct from commit `21c00841` — already-decrypt secrets
during deploy and forward them into `Cloudflare.Vite({ env: { ... } })`
so they live as Cloudflare Worker secrets — was right. ADR 0001's
characterization of this as "duplicating secret material" overweighted
the architectural cost (the codegen payload is the source of truth;
the Worker env is a derived view re-set on every deploy) and
underweighted the runtime savings. We're un-pivoting.

This ADR also cleans up how consumer code reads those secrets. Direct
`process.env.X` reads gave us no type safety, no redaction, and no
clear seam for testing. We adopt `effect/Config` (the standard
configuration-loading API in Effect 4) for typed, redacted access at
the consumer side, with `process.env` as its default backend (which is
exactly what we want post-build-time-injection).

## Decision

### Build-time env injection

Secrets travel through SOPS at *deploy* time. The flow is:

1. `apps/web/alchemy.run.ts` calls `loadDeployEnv("web", appEnv)`.
   This decrypts the per-app SOPS payload **and** the deploy-scope
   payload into the deploy process's `process.env`.
2. The same script forwards those values into
   `Cloudflare.Vite({ env: { ... } })`. The forwarded keys are:
   - `DATABASE_URL` — bound output of the per-deploy `NeonProject`
     (not a SOPS payload entry).
   - `BETTER_AUTH_SECRET` — required.
   - `POLAR_ACCESS_TOKEN`, `POLAR_WEBHOOK_SECRET`,
     `POLAR_PRO_PRODUCT_ID_PRODUCTION`,
     `POLAR_FREE_PRODUCT_ID_PRODUCTION` — optional. Each defaults to
     `""` so a missing-secret deploy still boots; consumer code treats
     `""` as "feature disabled" (`polarClient` stays `null`, the
     webhook plugin is not mounted).
3. Cloudflare stores the forwarded values as Worker secrets on the
   deployed script. Every Worker isolate boots with
   `process.env.BETTER_AUTH_SECRET` already populated. No per-isolate
   SOPS decrypt cost on the cold path.

`SOPS_AGE_KEY` is **not** forwarded. The Worker doesn't decrypt
anything at runtime; it doesn't need the key.

`@gen/env/runtime/loadAppEnv` stays in the codebase — it's still used
by non-Worker consumers (the Fly-deployed `apps/api`, local dev
scripts, `apps/*/alchemy.run.ts` deploy scripts). Only the web Worker
boot path stops calling it.

### Consumer-side reads via `effect/Config`

`@stackpanel/auth` reads the values it consumes through `effect/Config`,
not direct `process.env` access:

```ts
// packages/auth/src/config.ts
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Option from "effect/Option";
import * as Redacted from "effect/Redacted";

const program = Effect.gen(function* () {
  const betterAuthSecret = yield* Config.option(Config.redacted("BETTER_AUTH_SECRET"));
  const polarAccessToken = yield* Config.option(Config.redacted("POLAR_ACCESS_TOKEN"));
  // …
  return { betterAuthSecret, polarAccessToken /* … */ };
});

// Materialize once at module load. The default ConfigProvider
// (`ConfigProvider.fromEnv()`) reads `process.env`, which Cloudflare
// has already populated with the forwarded Worker secrets.
const resolved = Effect.runSync(program);

export const betterAuthSecret = resolved.betterAuthSecret;
export const polarAccessToken = resolved.polarAccessToken;
// …
```

Secrets are wrapped in `Redacted<string>` so accidental
`JSON.stringify` / `console.log` / structured-logging calls don't leak
them. The unwrap (`Redacted.value`) happens at exactly one boundary in
each call site — where the underlying SDK (better-auth, polar-sdk)
needs the raw string.

A pair of `presentString(opt)` / `presentRedacted(opt)` helpers in
`packages/auth/src/config.ts` collapse the forwarded `""` sentinel
back into `undefined` so call sites can use the familiar `if (value)`
shape.

### Why `effect/Config` and not `znv`?

`znv` is great for the once-per-deploy validation `loadDeployEnv` does
in `apps/*/alchemy.run.ts`. It validates a flat record at process
start with a Zod-backed schema, throws an actionable error if anything
is missing, and stops there. It does not give you `Redacted<T>` or a
`ConfigProvider` seam for testing; adding either would be re-inventing
half of `effect/Config`.

`effect/Config` is better-shaped for the *consumer* side because:

- `Redacted<string>` is a first-class output type. We get redaction
  with no extra wrapping.
- `Config.option`, `Config.withDefault`, `Config.orElse` cleanly model
  "feature disabled when missing" without each call site re-deriving
  it from `process.env`.
- The default `ConfigProvider` is `ConfigProvider.fromEnv()`, which
  reads `process.env`. Tests can swap it out with
  `ConfigProvider.fromUnknown({ ... })` via `Effect.provideService`.

We keep `znv` exactly where it is (deploy-scope validation in
`packages/znv` and its callers) and add `effect/Config` for in-app
consumption. No mass replacement, no sprawl.

## Consequences

### Pros

- **Zero per-request / per-isolate decrypt cost.** Workers boot with
  `process.env` already populated; the cold path is identical to
  reading any other Worker secret.
- **Encrypted at rest in Cloudflare's secret store.** Cloudflare
  encrypts Worker secrets at rest in their store; we don't need to
  ship our own ciphertext to get encrypted-at-rest behaviour.
- **No `SOPS_AGE_KEY` in Worker env.** One fewer secret bound to the
  Worker; one fewer rotation surface inside the runtime.
- **Typed, redacted consumer reads.** `effect/Config` gives us
  `Redacted<string>` types, an `Option`-based "feature disabled"
  shape, and a swappable `ConfigProvider` for tests. Linters and
  reviewers can spot a stray `Redacted.value` call instead of having
  to remember which `process.env.X` is sensitive.
- **Smaller blast radius for typos.** A misspelled key in a
  `Config.string("FOO_BR")` call still throws on missing data, and
  TypeScript doesn't help — but it does narrow the surface where such
  typos can appear, since every consumer goes through `config.ts`.

### Cons / trade-offs

- **Secrets exist in two places at deploy time.** They live in the
  codegen payload (`packages/gen/env/data/<env>/web.sops.json`) **and**
  in Cloudflare's Worker secret store after each deploy. The codegen
  payload remains the source of truth; the Worker env is a derived
  view re-set on every `vp build` → deploy run. This is the
  duplication ADR 0001 was right to flag, and the trade-off ADR 0001
  was wrong to make in the other direction: cold-start latency
  matters more than the architectural neatness of a single live copy.
- **Rotating a SOPS secret requires a redeploy** to propagate to live
  Workers. Workers cache their env across requests within an isolate,
  so a SOPS-only update without a redeploy will not take effect until
  the isolate is recycled. This is the same constraint that applies
  to *all* Worker secrets and is consistent with how we've always
  rotated Fly secrets (`fly secrets set` → restart). Acceptable.
- **Adding a new secret is a two-edit operation again.** Step 1: add
  the `sops:` entry in `.stack/config.apps.nix:envs.shared`. Step 2:
  forward it in `apps/web/alchemy.run.ts`'s `Cloudflare.Vite({ env })`.
  ADR 0001 wanted this to be a one-edit flow; we're giving that up.
  In practice the duplication is mechanical and obvious in code
  review, and a future improvement could codegen the forwarder list
  from the Nix scope.

### Trade-off vs ADR 0001

ADR 0001 prioritised "single source of truth at runtime" over
predictable cold-start latency. ADR 0003 inverts that priority.
Cold-start latency is user-visible and grows linearly with the
payload; the source-of-truth duplication is a deploy-time concern
that's mechanical to enforce in CI if it ever bites us.

## Alternatives considered

- **Keep ADR 0001 (runtime SOPS decrypt) — rejected.** Pays the
  AGE+SOPS decrypt cost on every cold isolate. Cost grows linearly
  with payload size. Cloudflare's isolate spawn pattern means the
  cold path is a non-trivial fraction of total requests at our scale.
- **Call `loadAppEnv` once per cold isolate but cache across requests
  within the isolate — rejected.** This is what ADR 0001 already
  does; the *first* request still pays the decrypt, and that's the
  cost we're refusing to pay.
- **Run a sidecar service that holds decrypted secrets and the Worker
  fetches them on boot — rejected.** Adds infra (one more service to
  deploy, monitor, secure), adds a request-time round-trip on cold
  paths, and doesn't save anything we can't get from Cloudflare's
  built-in Worker-secret machinery.
- **Use `znv` instead of `effect/Config` for consumer-side reads —
  rejected.** `znv` is already in use for deploy-scope validation;
  reusing it on the consumer side would force us to rebuild
  `Redacted<T>` and `ConfigProvider`-style swap-for-tests on top of
  it. `effect/Config` provides both off the shelf.
- **Replace `znv` everywhere with `effect/Config` — rejected as
  scope creep.** `znv` is the right tool for the once-per-deploy
  flat-record validation it currently performs in
  `apps/*/alchemy.run.ts`. We keep it where it is.

## References

- Implementation: branch `feat/build-time-env-effect-config`,
  PR (linked from this ADR after open).
- Forwarder: `apps/web/alchemy.run.ts` (the `Cloudflare.Vite({ env })`
  block).
- Consumer reads: `packages/auth/src/config.ts`,
  `packages/auth/src/index.ts`, `packages/auth/src/lib/payments.ts`.
- SOPS source declarations: `.stack/config.apps.nix:envs.shared`.
- Deploy-time decryption: `packages/infra/src/lib/deploy.ts`
  (`loadDeployEnv`).
- Effect Config docs: `effect@4.x`, `effect/Config` and
  `effect/ConfigProvider` modules. The default `ConfigProvider` is
  `fromEnv()`, which reads `process.env`.
- bd issues: `stackpanel-3tj` (waitlist auth-secret regression),
  `stackpanel-ayo` (BETTER_AUTH_SECRET="" in payloads).
- Superseded ADR: [0001](./0001-runtime-secrets-via-gen-env-loader.md).
- Related ADR: [0002](./0002-runtime-startup-migrations.md) — the
  migration TLA in `packages/auth/src/index.ts` reads `DATABASE_URL`
  via `process.env`. That value is also forwarded by the same
  `Cloudflare.Vite({ env })` block, so the two flows compose
  naturally.
