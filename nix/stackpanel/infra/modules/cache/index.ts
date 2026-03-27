// ==============================================================================
// Cache Infrastructure Module
//
// Provisions the appropriate cache/Redis backend based on environment:
//   - Upstash Redis (production / CI)
//   - Devenv Redis (local development with Nix)
//   - Docker Valkey (local development fallback)
//
// Inputs (from Nix via infra-inputs.json):
//   projectName: string
//   provider: "auto" | "upstash" | "devenv" | "docker"
//   upstash: { region, apiKeySsmPath, emailSsmPath }
//   devenv: { host, port }
//   docker: { image, tag, port, network }
//   ssm: { enable, pathPrefix }
//
// Outputs:
//   { redisUrl: string, redisToken: string, provider: string }
// ==============================================================================
import alchemy, { Resource } from "alchemy";
import type { Context } from "alchemy";
import { SSMParameter } from "alchemy/aws";
import { UpstashRedis } from "alchemy/upstash";
import * as docker from "alchemy/docker";
import Infra from "@stackpanel/infra";

// Try to import helpers from @gen/alchemy, fall back to inline
let getSSMSecret: (name: string) => Promise<string>;
try {
  const helpers = await import("@gen/alchemy/helpers");
  getSSMSecret = helpers.getSSMSecret;
} catch {
  getSSMSecret = async (name: string): Promise<string> => {
    const { SSMClient, GetParameterCommand } = await import(
      "@aws-sdk/client-ssm"
    );
    const client = new SSMClient({});
    const response = await client.send(
      new GetParameterCommand({ Name: name, WithDecryption: true }),
    );
    if (!response.Parameter?.Value) {
      throw new Error(`SSM Parameter ${name} not found or empty`);
    }
    return response.Parameter.Value;
  };
}

// ============================================================================
// Custom Resource: Devenv Redis (read-only reference)
// ============================================================================
interface DevenvRedisProps {
  port?: number;
  host?: string;
}

interface DevenvRedis extends DevenvRedisProps {
  connectionUrl: string;
}

const DevenvRedis = Resource(
  "devenv::Redis",
  async function (
    this: Context<DevenvRedis>,
    _id: string,
    props: DevenvRedisProps,
  ): Promise<DevenvRedis> {
    if (this.phase === "delete") {
      return this.destroy();
    }
    const host = props.host ?? "localhost";
    const port = props.port ?? 6379;
    const connectionUrl = `redis://${host}:${port}`;
    return { ...props, host, port, connectionUrl };
  },
);

// ============================================================================
// Module setup
// ============================================================================
const infra = new Infra("cache");
const inputs = infra.inputs(process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES);

const USE_DEVENV =
  process.env.IN_NIX_SHELL === "impure" ||
  process.env.DEVENV_ROOT !== undefined;
const USE_DOCKER = !USE_DEVENV && process.env.USE_DOCKER === "true";
const STAGE = process.env.STAGE || "dev";

// Resolve provider
let provider: string;
if (inputs.provider === "auto") {
  if (USE_DEVENV) provider = "devenv";
  else if (USE_DOCKER) provider = "docker";
  else provider = "upstash";
} else {
  provider = inputs.provider;
}

// ============================================================================
// Provision cache based on resolved provider
// ============================================================================
let redisUrl: string;
let redisToken: string = "";

switch (provider) {
  case "devenv": {
    const redis = await DevenvRedis(infra.id("devenv-redis"), {
      port: inputs.devenv.port,
      host: inputs.devenv.host,
    });
    redisUrl = redis.connectionUrl;
    console.log(`[cache] Using Devenv Redis: ${redisUrl}`);
    break;
  }

  case "docker": {
    const network = await docker.Network(infra.id("network"), {
      name: inputs.docker.network,
    });

    const volume = await docker.Volume(infra.id("redis-data"), {
      name: `${inputs.projectName}_redis_data`,
      labels: [
        { name: "app", value: inputs.projectName },
        { name: "service", value: "redis" },
      ],
    });

    const image = await docker.RemoteImage(infra.id("redis-image"), {
      name: inputs.docker.image,
      tag: inputs.docker.tag,
    });

    await docker.Container(infra.id("redis-container"), {
      name: `${inputs.projectName}-redis`,
      image: image.imageRef,
      networks: [{ name: network.name }],
      volumes: [
        {
          hostPath: volume.name,
          containerPath: "/data",
        },
      ],
      ports: [
        {
          internal: 6379,
          external: inputs.docker.port,
        },
      ],
      start: true,
    });

    redisUrl = `redis://localhost:${inputs.docker.port}`;
    console.log(`[cache] Using Docker Valkey: ${redisUrl}`);
    break;
  }

  case "upstash":
  default: {
    const upstashApiKey = await getSSMSecret(inputs.upstash.apiKeySsmPath);
    const upstashEmail = await getSSMSecret(inputs.upstash.emailSsmPath);

    const upstashRedis = await UpstashRedis(
      infra.id(`redis-${STAGE}`),
      {
        name: `${inputs.projectName}-${STAGE}`,
        primaryRegion: inputs.upstash.region,
        apiKey: alchemy.secret(upstashApiKey),
        email: upstashEmail,
      },
    );

    redisUrl = upstashRedis.endpoint;
    redisToken = upstashRedis.restToken.unencrypted;
    console.log(
      `[cache] Using Upstash Redis: ${upstashRedis.name} (${redisUrl})`,
    );

    // Optionally write to SSM
    if (inputs.ssm.enable) {
      await SSMParameter(infra.id("redis-url-ssm"), {
        name: `${inputs.ssm.pathPrefix}/${STAGE}/redis-url`,
        type: "String",
        value: redisUrl,
        description: `Redis URL for ${inputs.projectName} ${STAGE}`,
        tags: { app: inputs.projectName, stage: STAGE },
      });

      await SSMParameter(infra.id("redis-token-ssm"), {
        name: `${inputs.ssm.pathPrefix}/${STAGE}/redis-token`,
        type: "SecureString",
        value: alchemy.secret(redisToken),
        description: `Redis REST token for ${inputs.projectName} ${STAGE}`,
        tags: { app: inputs.projectName, stage: STAGE },
      });
    }
    break;
  }
}

// ============================================================================
// Outputs
// ============================================================================
export default {
  redisUrl,
  redisToken,
  provider,
};
