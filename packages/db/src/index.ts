import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as auth from "./schema/auth";
import * as organization from "./schema/organization";

const schema = { ...auth, ...organization };

let _db: ReturnType<typeof drizzle> | undefined;

/**
 * Drizzle client for Postgres via Hyperdrive (Cloudflare) or
 * DATABASE_URL (local dev). Lazily initialized and cached.
 */
export function getDb(connectionString?: string): ReturnType<typeof drizzle> {
  if (_db) return _db;

  const url = connectionString || process.env.DATABASE_URL;
  if (!url) {
    throw new Error("No database connection string provided and DATABASE_URL is not set");
  }

  const pool = new Pool({ connectionString: url, maxUses: 1 });
  _db = drizzle({ client: pool, schema });
  return _db;
}

/**
 * @deprecated Use getDb() instead. Kept for backward compatibility.
 */
export const db = new Proxy({} as ReturnType<typeof drizzle>, {
  get(_, prop) {
    return (getDb() as any)[prop];
  },
});

export { auth, organization };
