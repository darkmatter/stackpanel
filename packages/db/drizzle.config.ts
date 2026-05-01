import { defineConfig } from "drizzle-kit";

// `drizzle-kit generate` doesn't need the URL — it diffs the schema against
// the existing migrations. `drizzle-kit migrate` (and the runtime `migrate()`
// in `src/migrate.ts`) connect using `POSTGRES_URL`/`DATABASE_URL`. We accept
// either so local ad-hoc runs work in any devshell that already has one set.
const url =
  process.env.POSTGRES_URL ?? process.env.DATABASE_URL ?? "postgres://stub";

export default defineConfig({
  schema: "./src/schema",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: { url },
});
