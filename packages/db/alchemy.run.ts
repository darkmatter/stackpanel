import * as Stack from "alchemy-effect/Stack";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import {
  Container,
  Volume,
  NeonProject,
  providers as dockerProviders,
  neonProviders,
} from "./src/infra";

type DbProvider = "docker" | "neon" | "hyperdrive";

const dbProvider: DbProvider =
  (process.env.DB_PROVIDER as DbProvider | undefined) ??
  (process.env.NODE_ENV === "development" || !process.env.NODE_ENV
    ? "docker"
    : "hyperdrive");

console.log(`Database provider: ${dbProvider}`);

// ---------------------------------------------------------------------------
// Docker — local Postgres container
// ---------------------------------------------------------------------------

const POSTGRES_PORT = process.env.STACKPANEL_POSTGRES_PORT || "5432";
const POSTGRES_USER = "stackpanel";
const POSTGRES_PASSWORD = "stackpanel";
const POSTGRES_DB = "stackpanel";

const localDockerPostgres = Effect.gen(function* () {
  const pgData = yield* Volume("postgres-data", {
    name: "stackpanel-postgres-data",
  });

  yield* Container("postgres", {
    image: "postgres:17-alpine",
    name: "stackpanel-postgres",
    ports: [{ external: POSTGRES_PORT, internal: 5432 }],
    environment: {
      POSTGRES_USER,
      POSTGRES_PASSWORD,
      POSTGRES_DB,
      PGDATA: "/var/lib/postgresql/data/pgdata",
    },
    volumes: [
      {
        source: pgData.volumeName,
        target: "/var/lib/postgresql/data",
      },
    ],
    healthcheck: {
      cmd: ["pg_isready", "-U", POSTGRES_USER],
      interval: "5s",
      timeout: "5s",
      retries: 5,
      startPeriod: "10s",
    },
    restart: "unless-stopped",
  });

  return {
    connectionString: `postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}`,
    provider: "docker" as const,
  };
});

// ---------------------------------------------------------------------------
// Neon — on-demand managed Postgres project
// ---------------------------------------------------------------------------

const NEON_PROJECT_NAME = process.env.NEON_PROJECT_NAME || "stackpanel";
const NEON_REGION = process.env.NEON_REGION || "aws-us-east-1";

const neonManagedPostgres = Effect.gen(function* () {
  const project = yield* NeonProject("postgres", {
    name: NEON_PROJECT_NAME,
    regionId: NEON_REGION,
    pgVersion: 17,
    databaseName: "stackpanel",
    roleName: "stackpanel",
  });

  return {
    connectionString: project.connectionUri,
    provider: "neon" as const,
  };
});

// ---------------------------------------------------------------------------
// Hyperdrive — existing Postgres via Cloudflare (no provisioning)
// ---------------------------------------------------------------------------

const cloudflareHyperdrive = Effect.succeed({
  connectionString: process.env.DATABASE_URL ?? "hyperdrive://HYPERDRIVE",
  provider: "hyperdrive" as const,
});

// ---------------------------------------------------------------------------
// Stack
// ---------------------------------------------------------------------------

const allProviders = Layer.mergeAll(
  dockerProviders(),
  neonProviders(),
) as Layer.Layer<any, never, any>;

const dbEffect =
  dbProvider === "docker"
    ? localDockerPostgres
    : dbProvider === "neon"
      ? neonManagedPostgres
      : cloudflareHyperdrive;

export default Stack.make(
  "stackpanel-db",
  allProviders,
)(
  Effect.gen(function* () {
    return yield* dbEffect;
  }),
);
