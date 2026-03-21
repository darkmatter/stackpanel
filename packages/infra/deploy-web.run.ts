import alchemy from "alchemy";
import { Ec2Server } from "./deploy/ec2-server";

const region = process.env.AWS_REGION ?? "us-west-2";
const stage = process.env.STAGE ?? "staging";

const artifactBucket = requireEnv("EC2_ARTIFACT_BUCKET");
const artifactKey = requireEnv("EC2_ARTIFACT_KEY");
const artifactVersion = process.env.EC2_ARTIFACT_VERSION;

const password = process.env.ALCHEMY_PASSWORD;
if (!password) {
  throw new Error("ALCHEMY_PASSWORD is required (set it in SOPS or env)");
}

const app = await alchemy("stackpanel-web", {
  stage,
  password,
});

const STAGE_URL_DEFAULTS: Record<string, string> = {
  CORS_ORIGIN: stage === "prod" ? "https://stackpanel.com" : `http://${stage}.stackpanel.com`,
  BETTER_AUTH_URL: stage === "prod" ? "https://stackpanel.com" : `http://${stage}.stackpanel.com`,
  POLAR_SUCCESS_URL: stage === "prod" ? "https://stackpanel.com" : `http://${stage}.stackpanel.com`,
};

function resolveEnv(key: string, isSecret: boolean) {
  const value = process.env[key] ?? STAGE_URL_DEFAULTS[key] ?? "";
  const safeValue = value || "PLACEHOLDER";
  return isSecret ? alchemy.secret(safeValue) : safeValue;
}

const secretKeys = new Set(["DATABASE_URL", "BETTER_AUTH_SECRET", "POLAR_ACCESS_TOKEN"]);
const bindingKeys = ["DATABASE_URL", "CORS_ORIGIN", "BETTER_AUTH_SECRET", "BETTER_AUTH_URL", "POLAR_ACCESS_TOKEN", "POLAR_SUCCESS_URL"];

const environment: Record<string, any> = {};
for (const key of bindingKeys) {
  environment[key] = resolveEnv(key, secretKeys.has(key));
}

const server = await Ec2Server("web", {
  region,
  availabilityZone: process.env.EC2_AVAILABILITY_ZONE ?? `${region}a`,
  imageId: process.env.EC2_IMAGE_ID,
  instanceType: process.env.EC2_INSTANCE_TYPE ?? "t3.small",
  keyName: process.env.EC2_KEY_NAME,
  artifactBucket,
  artifactKey,
  artifactVersion,
  parameterPath: process.env.EC2_PARAMETER_PATH ?? `/stackpanel/${stage}/web-runtime`,
  httpCidrBlocks: ["0.0.0.0/0"],
  sshCidrBlocks: process.env.EC2_SSH_CIDRS?.split(",").map(s => s.trim()).filter(Boolean) ?? [],
  environment,
  tags: {
    App: "stackpanel",
    Stage: stage,
  },
});

console.log(`Web    -> ${server.url}`);
console.log(`SSH    -> ${server.publicDnsName}`);
console.log(`Artifact -> s3://${artifactBucket}/${artifactKey}`);

await app.finalize();

function requireEnv(name: string) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} environment variable is required`);
  }
  return value;
}
