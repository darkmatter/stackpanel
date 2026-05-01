# 0001 — Runtime secrets are decrypted via `@gen/env`, not forwarded as Worker env vars

- **Status**: Accepted
- **Date**: 2026-05-01

## Context

The waitlist join endpoint on `stackpanel.com` was crashing in
production with HTTP 500:

```
You are using the default secret. Please change it.
```

The crash originated inside `better-auth`'s `validateSecret` and
surfaced on every tRPC call (waitlist included), because
`createTRPCContext` eagerly reads `opts.auth.api.getSession(...)`.
Investigation (see commit `8a7897c6`) found that `BETTER_AUTH_SECRET`
and the four Polar secrets (`POLAR_ACCESS_TOKEN`,
`POLAR_WEBHOOK_SECRET`, `POLAR_PRO_PRODUCT_ID_PRODUCTION`,
`POLAR_FREE_PRODUCT_ID_PRODUCTION`) were declared in
`.stack/config.apps.nix:envs.shared` with `required = false` and **no
SOPS source**. As a result, `stackpanel codegen build` rendered
`"BETTER_AUTH_SECRET": ""` into every per-stage payload at
`packages/gen/env/data/<env>/web.sops.json`. Even after we wired the
SOPS sources, the payloads remained dead code in the web Worker
because nobody was decrypting them at runtime.

Two paths were available to fix this:

1. **Forward secrets via `Cloudflare.Vite({ env: { ... } })`** — read
   the values from `process.env` (populated at deploy time by
   `loadDeployEnv` reading the deploy scope) and shovel each one into
   the Cloudflare Worker's environment as a Worker secret. This is
   what commit `21c00841` did and what we are now reverting.
2. **Decrypt the embedded SOPS payload at Worker boot** via the
   existing `@gen/env/runtime` loader — give the Worker only the AGE
   key material and let it decrypt the rest.

Approach (1) duplicated secret material (Cloudflare's secret store
*and* the embedded SOPS payload), required every new secret to be
added in two places (`.stack/config.apps.nix` *and*
`apps/web/alchemy.run.ts`), and bypassed the very codegen pipeline
`@gen/env` was designed to be the single source of truth for. It also
made each new secret a deploy-script edit rather than a config-only
change.

Approach (2) was already 90% built: the per-app SOPS payload is
embedded in `packages/gen/env/src/runtime/generated-payloads/web/{dev,staging,prod}.ts`,
and `nix/stackpanel/lib/codegen/templates/env/loader.ts` is an
edge-safe loader (no FileSystem/ChildProcess dependency) that reads
ciphertext + `process.env.SOPS_AGE_KEY` and produces a decrypted
payload it can inject into `process.env`. It just wasn't wired into
the web Worker's boot path.

## Decision

Workers receive only `SOPS_AGE_KEY` (and a non-secret `APP_ENV`
discriminator) at deploy time. All other application secrets are
decrypted **inside the Worker** on boot via:

```ts
// apps/web/src/server.ts
import { loadAppEnv } from "@gen/env/runtime/edge";

const appEnv = process.env.APP_ENV ?? process.env.STAGE ?? "dev";

if (process.env.SOPS_AGE_KEY) {
  await loadAppEnv("web", appEnv, { inject: true });
}
```

The `@gen/env` package gains a new `./runtime/edge` export that maps
to `loader.ts` (the edge-safe loader). The existing `./runtime`
export — backed by `node-loader.ts` — keeps its FileSystem +
ChildProcessSpawner dependencies for use from `apps/*/alchemy.run.ts`
and other Node/Bun entrypoints.

Two changes complement the wiring:

1. **`@stackpanel/auth` is now lazy.** The `betterAuth({...})` call is
   moved into a `buildAuth()` function called by a `Proxy`-backed
   `auth` export. The first property access on `auth` builds and
   caches the instance. This guarantees that if the import chain
   `routeTree.gen.ts → routes/api/trpc.$.ts → @stackpanel/auth`
   resolves before the SSR entrypoint's top-level `await loadAppEnv`
   fires (which can happen depending on bundler module ordering),
   `betterAuth` is *not* called yet — and by the time the request
   handler actually touches `auth.api`, the env load is complete.

2. **The web Worker env in `apps/web/alchemy.run.ts` shrinks.** It
   keeps `DATABASE_URL` (a runtime-bound resource output from the
   Neon project, not a SOPS payload entry), and adds `SOPS_AGE_KEY`
   and `APP_ENV`. The five forwarded secrets from commit `21c00841`
   are removed.

Adding a new application secret going forward requires only:

1. A `sops:` entry in `.stack/config.apps.nix:envs.shared` (or the
   relevant scope) — i.e., one Nix file edit.
2. A re-run of `stackpanel codegen build` to refresh the embedded
   payload.

The new variable is automatically available on `process.env` inside
the Worker after the loader runs. No changes to `apps/web/alchemy.run.ts`,
no Cloudflare secret to provision, no per-environment dual-write.

## Consequences

**Pros**

- **Single source of truth.** Secrets are declared in Nix and embedded
  in the codegen payload. Adding a secret is a one-place change.
- **No dual-write.** No more "remember to also add this to
  `alchemy.run.ts`" trap.
- **Encrypted at rest until first request.** The Worker bundle ships
  with SOPS ciphertext, not cleartext secrets; the AGE key is the only
  cleartext-equivalent material in the Worker's secret store.
- **Smaller Cloudflare secret-store surface.** Only `SOPS_AGE_KEY` (+
  `DATABASE_URL`, which is a per-deploy resource, not a SOPS secret)
  needs to be a Worker secret. Previously every new secret added a new
  Worker secret entry per stage.
- **Mirrors the Fly-deployed `apps/api`.** The api app already loads
  its env via `loadAppEnv` at boot (in `apps/api/src/index.ts`'s
  upstream chain); the web Worker now follows the same pattern.

**Cons**

- **Cold-start cost.** The first request to a new Worker isolate pays
  the SOPS decrypt cost (one ChaCha20-Poly1305 decrypt per encrypted
  field, plus the AGE X25519 key derivation, ~tens of milliseconds for
  the current ~5-secret payload). Subsequent requests on the same
  isolate hit the in-memory cache in `loader.ts`. At our scale this is
  invisible. If we ever embed kilobyte-class secrets in the payload,
  revisit.
- **`SOPS_AGE_KEY` rotation now happens via the deploy scope only.**
  The CI workflow's `SECRETS_AGE_KEY_DEV` GitHub secret is the rotation
  target; rotating it requires a redeploy because the Worker reads it
  from the env binding set by `apps/web/alchemy.run.ts`, not from a
  Cloudflare secret store rotation. Trade-off accepted: rotations are
  rare and the deploy-scope rotation path is well-trodden (see
  `.github/workflows/secrets-codegen-check.yml`).
- **Every consumer of `@stackpanel/auth` now goes through a Proxy.**
  The Proxy is transparent for the property accesses better-auth and
  our consumers actually do (`auth.api.getSession`, `auth.handler`,
  etc.) but it's a small layer to keep in mind when debugging.

**Follow-ups / runbook**

- The `@gen/env` codegen drift gate (`.github/workflows/secrets-codegen-check.yml`)
  remains the canary for "someone edited a SOPS file but forgot to
  re-run codegen". This ADR doesn't change that workflow.
- Document `APP_ENV` as a load-bearing Worker env in
  `.stack/data/apps.web.env.nix` once the codegen surfaces non-secret
  defaults the same way it surfaces secrets.

## Alternatives considered

- **Forward secrets via `Cloudflare.Vite({ env: { ... } })` (commit
  `21c00841`)** — rejected: dual-write, duplicates secret material,
  bypasses `@gen/env` codegen.
- **Call `loadAppEnv(...)` inside each tRPC handler** — rejected:
  redundant decrypt cost on every request and no benefit over a single
  module-level decrypt cached for the isolate's lifetime.
- **Use Cloudflare KV / Secrets Store directly** — rejected: would
  require a separate sync pipeline alongside SOPS, and Cloudflare's
  per-secret API has its own rate-limit ceiling that we'd hit on every
  deploy that touches a payload.
- **Make `@stackpanel/auth` synchronous via a Layer/Effect injection
  pattern** — rejected as scope-creep. The Proxy-backed lazy singleton
  is a 30-line change with no consumer-side migration; an Effect-shape
  refactor is a separate, larger change.

## References

- Parent commit `8a7897c6` — wired `BETTER_AUTH_SECRET` and Polar
  secrets through `.stack/config.apps.nix` so the codegen embeds real
  ciphertext into each per-stage payload.
- Reverted commit `21c00841` — the rejected env-shovel approach.
- Edge-safe loader: `nix/stackpanel/lib/codegen/templates/env/loader.ts`.
- Codegen export wiring: `nix/stackpanel/lib/codegen/env-package.nix`
  (`./runtime/edge` export).
- Web Worker entrypoint: `apps/web/src/server.ts`.
- Web deploy script: `apps/web/alchemy.run.ts`.
- Lazy auth: `packages/auth/src/index.ts`.
- bd issue: `stackpanel-3tj`.
