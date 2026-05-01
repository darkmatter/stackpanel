# 0002 — Database migrations are applied programmatically at app startup, not via `drizzle-kit push`

- **Status:** Accepted
- **Date:** 2026-05-01
- **Deciders:** Stackpanel core team
- **Related:** [`docs/adr/0001-runtime-secrets-via-gen-env-loader.md`](./0001-runtime-secrets-via-gen-env-loader.md)
- **Implementation:** branch `feat/runtime-migrations`

## Context

Until now, Stackpanel's Drizzle-backed Postgres (Neon) used the
`bun run db:push` flow — a wrapper around `drizzle-kit push` — to keep
the database schema in lockstep with the TypeScript schema files under
`packages/db/src/schema/`. That approach has several problems we keep
running into:

1. **Humans-in-the-loop**: `db:push` is a manual step. It is trivially
   forgotten — most recently on PR #24, where the
   `waitlist.join` tRPC procedure 500'd against the per-PR Neon preview
   project with `Failed query: select "id" from "beta_waitlist"` because
   nobody had run `db:push` against that fresh database. The deploy
   pipeline has no way to know the schema is stale until a request hits a
   missing table.
2. **No audit trail**: `drizzle-kit push` diffs the live DB against the
   TypeScript schema and emits SQL on the fly. Nothing is checked into git,
   so we have no history of schema changes, no way to review one in a PR,
   and no `down` story when a change goes wrong.
3. **Preview DB priming is lazy**: per-PR preview deploys provision their
   Neon project on first deploy (see `apps/web/alchemy.run.ts`). The DB
   is empty until something writes to it; with `db:push` that "something"
   is a human running the right command at the right time, which doesn't
   happen.
4. **Drift between environments**: `db:push` is destructive — it reshapes
   the live DB to match the schema. In dev we shrug and let it drop a
   column; in prod we don't dare run it. So in practice prod uses
   ad-hoc SQL while dev uses `db:push`, and the two diverge over time.

The user-visible failure on PR #24 was the trigger: the waitlist signup
button on the `local.<stage>.stackpanel.com` preview returned a 500, and
the only fix was to `wrangler tail` the worker, infer the missing table,
and run `db:push` against the preview manually. That's not a flow we want
to ship to ourselves repeatedly — and certainly not to anyone using
Stackpanel as a starter template.

## Decision

Migrations are now **file-based**, **committed to git**, and **applied
programmatically at app startup** by the `@stackpanel/db` package itself.

Concretely:

- **Generation** is local-only. After editing a schema file under
  `packages/db/src/schema/`, run
  `bun run --cwd packages/db db:generate`. That invokes
  `drizzle-kit generate` (which writes `packages/db/drizzle/<NNNN>_<name>.sql`
  and `packages/db/drizzle/meta/_journal.json`) and then
  `scripts/bundle-migrations.ts`, which inlines every SQL file into
  `packages/db/src/migrations-bundle.generated.ts`. All three artifacts are
  checked into git.
- **Application** is automatic. `@stackpanel/db` exports `runMigrations(db)`
  from `src/migrate.ts`. `packages/auth/src/index.ts` awaits it at
  module-evaluation time (top-level await) **before** constructing the
  `betterAuth({...})` instance, so the per-isolate boot order is always
  `import db → await runMigrations(db) → betterAuth({...})`. Anything
  downstream that imports `auth` (the tRPC handler, route middleware,
  background jobs) inherits the dependency naturally — by the time
  `auth.api.getSession()` is callable, every committed migration has been
  applied.
- **Concurrency** is handled by a Postgres advisory lock
  (`pg_advisory_lock(0x4d495252::bigint)`) inside `applyMigrations`, so
  many isolates can call `runMigrations` simultaneously without racing
  on `__drizzle_migrations` row inserts. Per-isolate, the function caches
  the in-flight `Promise` so repeated callers reuse the same migrate run.
- **Idempotency** comes from the standard drizzle `__drizzle_migrations`
  table: each entry is keyed by its content-derived `tag`, and applied
  rows are skipped on subsequent boots.
- **`drizzle-kit push` is removed** from every workspace script
  (`package.json`, `packages/db/package.json`, `turbo.json`,
  `.stack/config.nix`). `drizzle-kit migrate` is kept under
  `bun run db:migrate` for local ad-hoc use only — production /
  staging / preview deployments never invoke it; they rely entirely on
  the `runMigrations` call at startup.

### Why not `drizzle-orm/node-postgres/migrator` directly?

The built-in migrator reads SQL files at runtime via `node:fs`. Inside a
Cloudflare Worker bundle that filesystem is empty — Vite/Rolldown bundles
JS modules but not arbitrary `.sql` files. We considered three options:

1. **Vite `import.meta.glob('drizzle/*.sql', { query: '?raw' })`** —
   works, but couples `@stackpanel/db` to a specific bundler and silently
   becomes a no-op anywhere Vite isn't in the loop (Bun scripts, ad-hoc
   tests, the Go-driven docs build).
2. **A Workers-native migrator from drizzle-orm itself** — none exists
   for the `node-postgres` adapter as of `drizzle-orm@0.45.1`. The
   `neon-http` migrator is HTTP-only and requires switching the runtime
   driver.
3. **Pre-bundle the SQL into a TypeScript module at generate time**
   (chosen). `scripts/bundle-migrations.ts` reads `drizzle/` and writes
   `src/migrations-bundle.generated.ts` with each migration inlined as a
   string. The runtime imports that module like any other TS module —
   works identically in Workers, Node, Bun, vitest, and any future runtime
   without bundler-specific magic.

## Consequences

### Positive

- **Zero-config preview DB priming**: a freshly-provisioned Neon project
  is brought up to schema by the first request that touches the auth
  module. PR #24's waitlist 500 cannot recur with this design.
- **Audit trail**: every schema change ships as a reviewable
  `packages/db/drizzle/<NNNN>_<name>.sql` diff in the PR that introduces
  it.
- **No human deploy step** for schema changes — the deploy pipeline stays
  identical for code-only and code-plus-schema changes.
- **Cross-runtime portability**: bundled migrations work in Cloudflare
  Workers, Node, Bun, vitest, and any future runtime without per-target
  build tweaks.
- **Rollback story** is back on the table: a future iteration can add
  `down.sql` files and a `--down` flag to `runMigrations` without
  re-architecting how migrations are discovered or transported.

### Negative / trade-offs

- **One-time cost on cold isolate boot**: the first request to a freshly
  spawned isolate pays the migration check (a single
  `SELECT hash FROM __drizzle_migrations` and the advisory-lock
  acquire/release). Steady-state requests pay nothing — the `inflight`
  Promise cache short-circuits. Worst case (cold + brand-new schema) is
  the time to apply pending migrations once per environment.
- **Schema changes need explicit migration review**: developers can no
  longer iterate by editing the schema and running `db:push`. The price
  is a `bun run db:generate` + a single committed SQL file. Worth it for
  the audit trail; everyone agrees this is a good trade.
- **`packages/db/src/migrations-bundle.generated.ts` must stay in sync
  with `drizzle/`**. The `db:generate` script chains both, and the
  `db:bundle` script can be re-run independently
  (`bun run --cwd packages/db db:bundle`) if someone manually edits a
  migration file. CI does not (yet) re-bundle and diff — see
  *Follow-ups*.

### Neutral

- The `__drizzle_migrations` table now exists in every environment. Same
  shape drizzle's built-in migrator uses, so future-us could swap to the
  upstream migrator if Workers ever ships a fully-compatible one.

## Alternatives considered

- **Keep `drizzle-kit push`**: rejected. It is the source of the
  problems described in *Context* — no audit trail, manual step, and the
  existing PR-24 outage is a direct consequence.
- **Run migrations only in CI before deploy**: rejected. Preview Neon
  projects are created lazily by `apps/web/alchemy.run.ts` during the
  Cloudflare Workers deploy itself; there is no "before deploy" moment
  where the preview DB exists but the worker doesn't. Adding a separate
  CI step that provisions the DB and migrates it before the deploy ran
  would double the preview latency and re-introduce a human-readable
  deploy graph.
- **Use Neon's branching for schema management**: rejected. Neon
  branching is great for forking *data* off main, but it doesn't replace
  a migration tool — it inherits whatever schema main has and gives no
  way to evolve schema in a feature branch without merging the schema
  change to main first. Orthogonal to this decision.

## Follow-ups

- Add a CI check (`verify` workflow) that runs
  `bun run --cwd packages/db db:bundle` and fails if the resulting diff
  isn't empty. This guarantees the bundle stays in lockstep with the SQL
  files.
- Add `down.sql` support to `scripts/bundle-migrations.ts` and a
  `runMigrations(db, { direction: "down", to: <tag> })` opt-in for
  emergency rollbacks.
- Consider exposing a `runMigrationsEffect(db)` Effect-native variant
  for callers that already live in an `Effect.gen` block (parity with
  `loadAppEnvEffect` from `@gen/env/runtime`).
