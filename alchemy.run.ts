import * as crypto from "node:crypto";
import type { Context } from "alchemy";
import alchemy, { Resource } from "alchemy";
import { SSMParameter } from "alchemy/aws";
import * as cloudflare from "alchemy/cloudflare";
import * as docker from "alchemy/docker";
import { NeonBranch, NeonProject } from "alchemy/neon";
import { UpstashRedis } from "alchemy/upstash";
import { config } from "dotenv";
import * as infra from "@stackpanel/infra";
import * as env from "@stackpanel/env";

console.log(env.web.dev.env.POSTGRES_URL);

// ----------------------------------------------------------------------------
// Helper: Read secrets from SSM (for API keys that are pre-populated)
// ----------------------------------------------------------------------------
async function getSSMSecret(name: string): Promise<string> {
  // biome-ignore lint: Alchemy provides @aws-sdk/client-ssm as a peer dependency
  // @ts-ignore - peer dependency
  const { SSMClient, GetParameterCommand } =
    await import("@aws-sdk/client-ssm");
  const client = new SSMClient({});
  const response = await client.send(
    new GetParameterCommand({
      Name: name,
      WithDecryption: true,
    }),
  );
  if (!response.Parameter?.Value) {
    throw new Error(`SSM Parameter ${name} not found or empty`);
  }
  return response.Parameter.Value;
}

// Get Alchemy password from env var or SSM for remote state
let alchemyPassword = process.env.ALCHEMY_PASSWORD;
if (!alchemyPassword) {
  try {
    // Try to get from SSM if not in env (for CI/CD)
    alchemyPassword = await getSSMSecret("/common/alchemy-password");
    console.log("Using Alchemy password from SSM");
  } catch (error) {
    // For local development without SSM, use a default
    alchemyPassword = "local-dev-password";
    console.log("Using default local Alchemy password");
  }
}

const app = await alchemy("stackpanel", {
  password: alchemyPassword,
});

// ----------------------------------------------------------------------------
// Configuration
// ----------------------------------------------------------------------------
const USE_DEVENV =
  process.env.IN_NIX_SHELL === "impure" ||
  process.env.DEVENV_ROOT !== undefined;
const USE_DOCKER = !USE_DEVENV && process.env.USE_DOCKER === "true";
const STAGE = process.env.STAGE || "dev";
const IS_PREVIEW = STAGE !== "prod" && STAGE !== "dev";

// ----------------------------------------------------------------------------
// Helper: Compute stable port from project name (mirrors Nix mkProjectPort)
// ----------------------------------------------------------------------------
function computeProjectPort(
  name: string,
  minPort = 3000,
  portRange = 7000,
): number {
  const hash = crypto.createHash("md5").update(name).digest("hex");
  const portOffset = Number.parseInt(hash.substring(0, 4), 16);
  return minPort + (portOffset % portRange);
}

// ----------------------------------------------------------------------------
// Custom Resource: Devenv Postgres (read-only reference to devenv service)
// ----------------------------------------------------------------------------
interface DevenvPostgresProps {
  /** Database name */
  database: string;
  /** Username */
  user: string;
  /** Password */
  password: string;
  /** Port (defaults to 5432) */
  port?: number;
  /** Host (defaults to localhost) */
  host?: string;
}

interface DevenvPostgres extends DevenvPostgresProps {
  /** Connection URL */
  connectionUrl: string;
}

const DevenvPostgres = Resource(
  "devenv::Postgres",
  async function (
    this: Context<DevenvPostgres>,
    _id: string,
    props: DevenvPostgresProps,
  ): Promise<DevenvPostgres> {
    // This is a read-only reference - no create/update/delete needed
    if (this.phase === "delete") {
      return this.destroy();
    }

    const host = props.host ?? "localhost";
    const port = props.port ?? 5432;
    const connectionUrl = `postgresql://${props.user}:${props.password}@${host}:${port}/${props.database}`;

    return {
      ...props,
      host,
      port,
      connectionUrl,
    };
  },
);

// ----------------------------------------------------------------------------
// Custom Resource: Devenv Redis (read-only reference to devenv service)
// ----------------------------------------------------------------------------
interface DevenvRedisProps {
  /** Port (defaults to 6379) */
  port?: number;
  /** Host (defaults to localhost) */
  host?: string;
}

interface DevenvRedis extends DevenvRedisProps {
  /** Connection URL */
  connectionUrl: string;
}

const DevenvRedis = Resource(
  "devenv::Redis",
  async function (
    this: Context<DevenvRedis>,
    _id: string,
    props: DevenvRedisProps,
  ): Promise<DevenvRedis> {
    // This is a read-only reference - no create/update/delete needed
    if (this.phase === "delete") {
      return this.destroy();
    }

    const host = props.host ?? "localhost";
    const port = props.port ?? 6379;
    const connectionUrl = `redis://${host}:${port}`;

    return {
      ...props,
      host,
      port,
      connectionUrl,
    };
  },
);

// ----------------------------------------------------------------------------
// Custom Resource: Devenv Caddy (read-only reference to devenv Caddy service)
// ----------------------------------------------------------------------------
interface DevenvCaddyProps {
  /** Project name for computing stable port */
  projectName: string;
  /** Override the computed port */
  port?: number;
  /** Virtual host domain */
  domain?: string;
}

interface DevenvCaddy extends DevenvCaddyProps {
  /** Computed stable port */
  projectPort: number;
  /** URL to access the service */
  url: string;
}

const DevenvCaddy = Resource(
  "devenv::Caddy",
  async function (
    this: Context<DevenvCaddy>,
    _id: string,
    props: DevenvCaddyProps,
  ): Promise<DevenvCaddy> {
    if (this.phase === "delete") {
      return this.destroy();
    }

    const projectPort = props.port ?? computeProjectPort(props.projectName);
    const domain = props.domain ?? `${props.projectName}.localhost`;
    const url = `http://${domain}`;

    return {
      ...props,
      projectPort,
      url,
    };
  },
);

// ============================================================================
// Database: Devenv Postgres (Local) or Neon (Production) or Docker (Fallback)
// ============================================================================
let databaseUrl: string;
let neonProject: Awaited<ReturnType<typeof NeonProject>> | undefined;

if (USE_DEVENV) {
  // Use devenv-managed Postgres (matches services.nix configuration)
  const devenvPostgres = await DevenvPostgres("devenv_postgres", {
    database: "stackpanel",
    user: "pguser",
    password: "password",
    port: 5432,
  });

  databaseUrl = devenvPostgres.connectionUrl;
  console.log("Using Devenv Postgres:", databaseUrl);
} else if (USE_DOCKER) {
  // Docker Postgres for local development (fallback when not in devenv)
  const network = await docker.Network("stackpanel_network", {
    name: "stackpanel_network",
  });

  const postgresVolume = await docker.Volume("postgres_data", {
    name: "postgres_data",
    labels: [
      { name: "app", value: "stackpanel" },
      { name: "service", value: "postgres" },
    ],
  });

  const postgresImage = await docker.RemoteImage("postgres_image", {
    name: "postgres",
    tag: "16-alpine",
  });

  await docker.Container("postgres_container", {
    name: "stackpanel-postgres",
    image: postgresImage.imageRef,
    networks: [{ name: network.name }],
    volumes: [
      {
        hostPath: postgresVolume.name,
        containerPath: "/var/lib/postgresql/data",
      },
    ],
    environment: {
      POSTGRES_USER: "stackpanel",
      POSTGRES_PASSWORD: "stackpanel",
      POSTGRES_DB: "stackpanel",
    },
    ports: [
      {
        internal: 5432,
        external: 5432,
      },
    ],
    start: true,
  });

  databaseUrl = "postgresql://stackpanel:stackpanel@localhost:5432/stackpanel";
  console.log("Using Docker Postgres:", databaseUrl);
} else {
  // Read Neon API key from SSM (pre-populated)
  const neonApiKey = await getSSMSecret("/common/neon-api-key");

  // Create Neon project (or adopt existing)
  neonProject = await NeonProject("stackpanel_neon_project", {
    name: "stackpanel",
    apiKey: alchemy.secret(neonApiKey),
    region_id: "aws-us-east-1",
    pg_version: 16,
  });

  // For preview branches, create a separate Neon branch
  if (IS_PREVIEW) {
    const previewBranch = await NeonBranch(`neon_branch_${STAGE}`, {
      project: neonProject,
      name: STAGE,
      apiKey: alchemy.secret(neonApiKey),
      endpoints: [{ type: "read_write" }],
    });
    const connUri = previewBranch.connectionUris[0];
    if (!connUri) {
      throw new Error(`No connection URI available for branch ${STAGE}`);
    }
    databaseUrl = connUri.connection_uri.unencrypted;
    console.log("Using Neon Preview Branch:", previewBranch.name);
  } else {
    // Use main branch for dev/prod
    databaseUrl = neonProject.connection_uris[0].connection_uri.unencrypted;
    console.log(
      "Using Neon Database:",
      neonProject.name,
      "Branch:",
      neonProject.branch.name,
    );
  }

  // Write database URL to SSM so other services can read it
  await SSMParameter("database_url", {
    name: `/stackpanel/${STAGE}/database-url`,
    type: "SecureString",
    value: alchemy.secret(databaseUrl),
    description: `Database connection URL for stackpanel ${STAGE}`,
    tags: {
      app: "stackpanel",
      stage: STAGE,
    },
  });
}

// ============================================================================
// Cache: Devenv Redis (Local) or Upstash Redis (Production) or Docker (Fallback)
// ============================================================================
let redisUrl: string;
let redisToken: string | undefined;

if (USE_DEVENV) {
  // Use devenv-managed Redis (matches services.nix configuration)
  const devenvRedis = await DevenvRedis("devenv_redis", {
    port: 6379, // devenv default
  });

  redisUrl = devenvRedis.connectionUrl;
  console.log("Using Devenv Redis:", redisUrl);
} else if (USE_DOCKER) {
  // Docker Valkey for local development (fallback when not in devenv)
  const network = await docker.Network("stackpanel_network", {
    name: "stackpanel_network",
  });

  const redisVolume = await docker.Volume("redis_data", {
    name: "redis_data",
    labels: [
      { name: "app", value: "stackpanel" },
      { name: "service", value: "redis" },
    ],
  });

  const redisImage = await docker.RemoteImage("redis_image", {
    name: "valkey/valkey",
    tag: "latest",
  });

  await docker.Container("redis_container", {
    name: "stackpanel-redis",
    image: redisImage.imageRef,
    networks: [{ name: network.name }],
    volumes: [
      {
        hostPath: redisVolume.name,
        containerPath: "/data",
      },
    ],
    ports: [
      {
        internal: 6379,
        external: 6379,
      },
    ],
    start: true,
  });

  redisUrl = "redis://localhost:6379";
  console.log("Using Docker Valkey:", redisUrl);
} else {
  // Read Upstash credentials from SSM (pre-populated)
  const upstashApiKey = await getSSMSecret("/common/upstash-api-key");
  const upstashEmail = await getSSMSecret("/common/upstash-email");

  // Create Upstash Redis (unique per stage for preview branches)
  const upstashRedis = await UpstashRedis(`stackpanel_redis_${STAGE}`, {
    name: `stackpanel-${STAGE}`,
    primaryRegion: "us-east-1",
    apiKey: alchemy.secret(upstashApiKey),
    email: upstashEmail,
  });

  redisUrl = upstashRedis.endpoint;
  redisToken = upstashRedis.restToken.unencrypted;
  console.log("Using Upstash Redis:", upstashRedis.name, "Endpoint:", redisUrl);

  // Write Redis connection info to SSM
  await SSMParameter("redis_url", {
    name: `/stackpanel/${STAGE}/redis-url`,
    type: "String",
    value: redisUrl,
    description: `Redis URL for stackpanel ${STAGE}`,
    tags: {
      app: "stackpanel",
      stage: STAGE,
    },
  });

  await SSMParameter("redis_token", {
    name: `/stackpanel/${STAGE}/redis-token`,
    type: "SecureString",
    value: alchemy.secret(redisToken),
    description: `Redis REST token for stackpanel ${STAGE}`,
    tags: {
      app: "stackpanel",
      stage: STAGE,
    },
  });
}

// ============================================================================
// Caddy: Devenv-managed reverse proxy with stable port
// ============================================================================
let caddyConfig: Awaited<ReturnType<typeof DevenvCaddy>> | undefined;
let devServerPort = 3000; // default port

if (USE_DEVENV) {
  // Use devenv-managed Caddy with computed stable port
  caddyConfig = await DevenvCaddy("devenv_caddy", {
    projectName: "stackpanel",
    domain: "stackpanel.localhost",
  });

  // The dev server should run on the port that Caddy proxies to (3001 per services.nix)
  devServerPort = 3001;
  console.log(
    `Using Devenv Caddy: ${caddyConfig.url} (project port: ${caddyConfig.projectPort})`,
  );
}

// ============================================================================
// Cloudflare Workers
// ============================================================================
export const web = await cloudflare.Vite("web", {
  cwd: "apps/web",
  assets: "dist",
  bindings: {
    VITE_SERVER_URL: process.env.VITE_SERVER_URL || "",
  },
  dev: {
    command: "bun run dev",
  },
});

export const server = await cloudflare.Worker("server", {
  cwd: "apps/server",
  entrypoint: "src/index.ts",
  compatibility: "node",
  bindings: {
    // Database (Devenv, Neon, or Docker Postgres)
    DATABASE_URL: alchemy.secret(databaseUrl),

    // Cache (Devenv, Upstash, or Docker Valkey)
    REDIS_URL: redisUrl,
    ...(redisToken
      ? { UPSTASH_REDIS_REST_TOKEN: alchemy.secret(redisToken) }
      : {}),

    // Auth & API
    CORS_ORIGIN: process.env.CORS_ORIGIN || "",
    ...(process.env.BETTER_AUTH_SECRET
      ? { BETTER_AUTH_SECRET: alchemy.secret(process.env.BETTER_AUTH_SECRET) }
      : {}),
    BETTER_AUTH_URL: process.env.BETTER_AUTH_URL || "",
    ...(process.env.GOOGLE_GENERATIVE_AI_API_KEY
      ? {
          GOOGLE_GENERATIVE_AI_API_KEY: alchemy.secret(
            process.env.GOOGLE_GENERATIVE_AI_API_KEY,
          ),
        }
      : {}),
    ...(process.env.POLAR_ACCESS_TOKEN
      ? { POLAR_ACCESS_TOKEN: alchemy.secret(process.env.POLAR_ACCESS_TOKEN) }
      : {}),
    POLAR_SUCCESS_URL: process.env.POLAR_SUCCESS_URL || "",
  },
  dev: {
    port: devServerPort,
  },
});

// ============================================================================
// Exports
// ============================================================================
export { databaseUrl, redisUrl, redisToken, caddyConfig };

console.log(`Web    -> ${web.url}`);
console.log(`Server -> ${server.url}`);
if (caddyConfig) {
  console.log(`Caddy  -> ${caddyConfig.url}`);
}

await app.finalize();
