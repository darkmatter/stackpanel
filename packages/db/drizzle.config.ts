import { env } from "@gen/env/web";
import dotenv from "dotenv";
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  schema: "./src/schema",
  out: "./src/migrations",
  dialect: "postgresql",
  dbCredentials: {
    url: env.POSTGRES_URL,
  },
});
