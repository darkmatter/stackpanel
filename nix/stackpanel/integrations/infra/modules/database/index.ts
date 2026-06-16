// ==============================================================================
// Database Infrastructure Module
//
// Provisions the appropriate database backend based on environment:
//   - Neon Postgres (production / CI)
//   - Docker Postgres (local development fallback)
//
// Inputs (from Nix via infra-inputs.json):
//   projectName: string
//   name: string (database name)
//   provider: "auto" | "neon" | "docker"
//   neon: { region, pgVersion, apiKeySsmPath, enable-branching }
//   docker: { image, tag, user, password, port, network }
//   ssm: { enable, pathPrefix }
//
// Outputs:
//   { databaseUrl: string, provider: string }
// ==============================================================================
import alchemy from "alchemy";
import { SSMParameter } from "alchemy/aws";
import { NeonBranch, NeonProject } from "alchemy/neon";
import * as docker from "alchemy/docker";
import Infra from "@stackpanel/infra";

// Try to import helpers from @gen/alchemy, fall back to inline
let getSSMSecret: (name: string) => Promise<string>;
try {
  const helpers = await import("@gen/alchemy/helpers");
  getSSMSecret = helpers.getSSMSecret;
} catch {
  // Fallback: inline SSM helper
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
// Module setup
// ============================================================================
const infra = new Infra("database");
const inputs = infra.inputs(process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES);

const USE_DOCKER = process.env.USE_DOCKER === "true";
const STAGE = process.env.STAGE || "dev";
const IS_PREVIEW = STAGE !== "prod" && STAGE !== "dev";

// Resolve provider
let provider: string;
if (inputs.provider === "auto") {
  if (USE_DOCKER) provider = "docker";
  else provider = "neon";
} else {
  provider = inputs.provider;
}

// ============================================================================
// Provision database based on resolved provider
// ============================================================================
let databaseUrl: string;

switch (provider) {
  case "docker": {
    const network = await docker.Network(infra.id("network"), {
      name: inputs.docker.network,
    });

    const volume = await docker.Volume(infra.id("postgres-data"), {
      name: `${inputs.name}_postgres_data`,
      labels: [
        { name: "app", value: inputs.projectName },
        { name: "service", value: "postgres" },
      ],
    });

    const image = await docker.RemoteImage(infra.id("postgres-image"), {
      name: inputs.docker.image,
      tag: inputs.docker.tag,
    });

    await docker.Container(infra.id("postgres-container"), {
      name: `${inputs.projectName}-postgres`,
      image: image.imageRef,
      networks: [{ name: network.name }],
      volumes: [
        {
          hostPath: volume.name,
          containerPath: "/var/lib/postgresql/data",
        },
      ],
      environment: {
        POSTGRES_USER: inputs.docker.user,
        POSTGRES_PASSWORD: inputs.docker.password,
        POSTGRES_DB: inputs.name,
      },
      ports: [
        {
          internal: 5432,
          external: inputs.docker.port,
        },
      ],
      start: true,
    });

    databaseUrl = `postgresql://${inputs.docker.user}:${inputs.docker.password}@localhost:${inputs.docker.port}/${inputs.name}`;
    console.log(`[database] Using Docker Postgres: ${databaseUrl}`);
    break;
  }

  case "neon":
  default: {
    const neonApiKey = await getSSMSecret(inputs.neon.apiKeySsmPath);

    const neonProject = await NeonProject(infra.id("neon-project"), {
      name: inputs.name,
      apiKey: alchemy.secret(neonApiKey),
      region_id: inputs.neon.region,
      pg_version: inputs.neon.pgVersion,
    });

    if (IS_PREVIEW && inputs.neon["enable-branching"]) {
      // Create a separate branch for preview environments
      const previewBranch = await NeonBranch(infra.id(`neon-branch-${STAGE}`), {
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
      console.log(
        `[database] Using Neon Preview Branch: ${previewBranch.name}`,
      );
    } else {
      databaseUrl =
        neonProject.connection_uris[0].connection_uri.unencrypted;
      console.log(
        `[database] Using Neon: ${neonProject.name} (branch: ${neonProject.branch.name})`,
      );
    }

    // Optionally write to SSM
    if (inputs.ssm.enable) {
      await SSMParameter(infra.id("database-url-ssm"), {
        name: `${inputs.ssm.pathPrefix}/${STAGE}/database-url`,
        type: "SecureString",
        value: alchemy.secret(databaseUrl),
        description: `Database connection URL for ${inputs.projectName} ${STAGE}`,
        tags: {
          app: inputs.projectName,
          stage: STAGE,
        },
      });
    }
    break;
  }
}

// ============================================================================
// Outputs
// ============================================================================
export default {
  databaseUrl,
  provider,
};
