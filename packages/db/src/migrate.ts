// Programmatic Drizzle migrator that runs at app startup.
//
// Why a custom migrator?
//   `drizzle-orm/node-postgres/migrator` reads SQL files at runtime via
//   `node:fs`, which is empty inside a Cloudflare Worker bundle. We pre-bundle
//   every migration into `migrations-bundle.generated.ts` (see
//   `scripts/bundle-migrations.ts`) so the SQL ships with the Worker, then
//   apply each entry in order against `__drizzle_migrations`.
//
// Concurrency:
//   Cloudflare may spin up many isolates simultaneously, each calling
//   `runMigrations()` on cold start. We grab a transaction-scoped Postgres
//   advisory lock around each individual migration so concurrent isolates
//   serialise correctly. We deliberately do *not* use the session-scoped
//   `pg_advisory_lock` — that lock persists when the pg.Pool connection is
//   returned to the pool, so the next checkout would see "already locked
//   by you" semantics that deadlock the next isolate. Transaction-scoped
//   locks (`pg_advisory_xact_lock`) auto-release at COMMIT/ROLLBACK and
//   are immune to pool lifecycle weirdness.
//
//   Per-isolate, the function caches the in-flight Promise so repeated
//   callers reuse the same migrate run. On error the cache is cleared so
//   the next request retries from scratch.

import { sql } from "drizzle-orm";
import type { Db } from "./index";
import { type BundledMigration, MIGRATIONS_BUNDLE } from "./migrations-bundle.generated";

// Stable lock key. Picked once and never changed — must fit in a
// Postgres int8 (bigint). Using a plain JS number keeps drizzle's
// parameter binding simple (no bigint serialisation surprises).
const MIGRATION_LOCK_KEY = 1_296_127_570; // crc32-ish "stackpanel.db.migrations"

let inflight: Promise<void> | null = null;

/**
 * Apply every bundled migration that hasn't run yet against `db`.
 *
 * Idempotent and safe to call from many concurrent isolates: each pending
 * migration runs inside its own transaction with a `pg_advisory_xact_lock`,
 * and the per-isolate `inflight` cache deduplicates repeated calls within
 * the same JS runtime.
 *
 * @example
 * import { db, runMigrations } from "@stackpanel/db";
 * await runMigrations(db);
 */
export async function runMigrations(db: Db): Promise<void> {
  if (inflight) return inflight;
  inflight = applyMigrations(db).catch((err) => {
    inflight = null;
    throw err;
  });
  return inflight;
}

async function applyMigrations(db: Db): Promise<void> {
  // Snapshot whether `__drizzle_migrations` exists *before* we CREATE it,
  // so we can distinguish "fresh DB" from "DB managed by a prior tool"
  // (the legacy `db:push` flow) when deciding whether to apply 0000_init.
  const tableCheck = await db.execute<{ exists: boolean }>(sql`
    SELECT EXISTS (
      SELECT 1
        FROM pg_tables
       WHERE schemaname = 'public'
         AND tablename  = '__drizzle_migrations'
    ) AS "exists"
  `);
  const migrationsTableExisted = Boolean(tableCheck.rows[0]?.exists);

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS "__drizzle_migrations" (
      "id" SERIAL PRIMARY KEY,
      "hash" TEXT NOT NULL UNIQUE,
      "created_at" BIGINT NOT NULL
    )
  `);

  // Production-rollout safety net: if we just created `__drizzle_migrations`
  // and the public schema already has tables, infer the schema was managed
  // externally (the legacy `db:push` flow) and fast-forward every bundled
  // migration to "already applied". Without this, the first deploy after
  // this change would try to `CREATE TABLE "account"` against a DB that
  // already has it and abort the migrate run. This is a one-time event
  // per environment; subsequent deploys see the table and the normal
  // diff-and-apply flow takes over.
  if (!migrationsTableExisted) {
    const otherTables = await db.execute<{ count: number }>(sql`
      SELECT COUNT(*)::int AS "count"
        FROM pg_tables
       WHERE schemaname = 'public'
         AND tablename != '__drizzle_migrations'
    `);
    const hasExistingSchema = (otherTables.rows[0]?.count ?? 0) > 0;
    if (hasExistingSchema) {
      console.warn(
        "[runMigrations] detected an externally-managed Postgres schema; " +
          "fast-forwarding bundled migrations to applied without re-running SQL",
      );
      for (const entry of MIGRATIONS_BUNDLE) {
        await db.execute(sql`
          INSERT INTO "__drizzle_migrations" ("hash", "created_at")
          VALUES (${entry.tag}, ${Date.now()})
          ON CONFLICT ("hash") DO NOTHING
        `);
      }
      return;
    }
  }

  // Apply pending migrations one at a time. Each migration runs inside its
  // own transaction with a `pg_advisory_xact_lock` — the lock serialises
  // concurrent isolates, the transaction makes SQL + journal-row insert
  // atomic, and the lock auto-releases at COMMIT so we don't leak it back
  // into the connection pool.
  const ordered = [...MIGRATIONS_BUNDLE].sort((a, b) => a.idx - b.idx);
  for (const entry of ordered) {
    await applyOne(db, entry);
  }
}

async function applyOne(db: Db, entry: BundledMigration): Promise<void> {
  await db.transaction(async (tx) => {
    await tx.execute(sql`SELECT pg_advisory_xact_lock(${MIGRATION_LOCK_KEY})`);

    // Re-check applied status *inside* the lock — another isolate may have
    // applied this migration between our outer check and the lock acquire.
    const exists = await tx.execute<{ hash: string }>(
      sql`SELECT "hash" FROM "__drizzle_migrations" WHERE "hash" = ${entry.tag}`,
    );
    if (exists.rows.length > 0) return;

    const statements = splitStatements(entry.sql, entry.breakpoints);
    for (const stmt of statements) {
      if (!stmt) continue;
      await tx.execute(sql.raw(stmt));
    }
    await tx.execute(
      sql`INSERT INTO "__drizzle_migrations" ("hash", "created_at") VALUES (${entry.tag}, ${Date.now()})`,
    );
  });
}

function splitStatements(rawSql: string, hasBreakpoints: boolean): string[] {
  // Drizzle inserts `--> statement-breakpoint` between statements when it
  // generates the SQL. Splitting on the breakpoint preserves multi-statement
  // semantics (each gets its own `tx.execute`), which is required for things
  // like `CREATE INDEX CONCURRENTLY` and just generally avoids client-side
  // SQL parsing bugs. Older migrations without breakpoints fall back to a
  // single execute — Postgres handles multi-statement strings just fine.
  if (!hasBreakpoints) return [rawSql.trim()];
  return rawSql
    .split(/-->\s*statement-breakpoint/i)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/**
 * Test-only escape hatch — clears the per-isolate dedup cache so a second
 * `runMigrations(db)` actually runs against a fresh database in unit tests.
 * Production callers should never need this.
 *
 * @internal
 */
export function __resetMigrationCache(): void {
  inflight = null;
}
