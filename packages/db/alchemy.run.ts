import { loadAppEnv } from "@gen/env/runtime";
await loadAppEnv("web", "dev", { inject: true });
import * as Alchemy from "alchemy";
import type { NeonRegion } from "@alchemy.run/neon";
import * as Output from "alchemy/Output";
import { localState } from "alchemy/State";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";
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
    connectionString: Redacted.make(`postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}`),
    provider: "docker" as const,
  };
});

// ---------------------------------------------------------------------------
// Neon — on-demand managed Postgres project
// ---------------------------------------------------------------------------

const NEON_PROJECT_NAME = process.env.NEON_PROJECT_NAME || "stackpanel";
// The provider exports its region union, but not a runtime parser.
const neonRegions = [
  "aws-us-east-1", "aws-us-east-2", "aws-us-west-2", "aws-eu-central-1",
  "aws-eu-west-2", "aws-ap-southeast-1", "aws-ap-southeast-2", "aws-sa-east-1",
  "azure-eastus2", "azure-westus3", "azure-gwc",
] as const satisfies readonly NeonRegion[];

const neonManagedPostgres = Effect.gen(function* () {
  const configuredRegion = process.env.NEON_REGION || "aws-us-east-1";
  const region = neonRegions.find((candidate) => candidate === configuredRegion);
  if (!region) throw new Error(`NEON_REGION must be one of: ${neonRegions.join(", ")}`);

  const project = yield* NeonProject("postgres", {
    name: NEON_PROJECT_NAME,
    region,
    pgVersion: 17,
    databaseName: "stackpanel",
    roleName: "stackpanel",
  });

  return {
    connectionString: Output.map(project.connectionUri, (uri) => Redacted.make(uri)),
    provider: "neon" as const,
  };
});

// ---------------------------------------------------------------------------
// Hyperdrive — existing Postgres via Cloudflare (no provisioning)
// ---------------------------------------------------------------------------

const cloudflareHyperdrive = Effect.succeed({
  connectionString: Redacted.make(process.env.DATABASE_URL ?? "hyperdrive://HYPERDRIVE"),
  provider: "hyperdrive" as const,
});

// ---------------------------------------------------------------------------
// Stack
// ---------------------------------------------------------------------------

const allProviders = Layer.mergeAll(dockerProviders(), neonProviders());

const dbEffect =
  dbProvider === "docker"
    ? localDockerPostgres
    : dbProvider === "neon"
      ? neonManagedPostgres
      : cloudflareHyperdrive;

export default Alchemy.Stack(
  "stackpanel-db",
  {
    providers: allProviders,
    // `db:up` is a local-only entrypoint (Docker / Neon project / Hyperdrive
    // binding) and only loads `loadAppEnv("web", "dev")` — it deliberately
    // doesn't pull deploy-scope Cloudflare creds, so picking
    // `Cloudflare.state()` here would fail to authenticate. Filesystem state
    // under `.alchemy/` matches the previous behaviour and works without
    // any cloud credentials.
    state: localState(),
  },
  Effect.gen(function* () {
    return yield* dbEffect;
  }),
);
