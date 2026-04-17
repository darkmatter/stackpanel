// ==============================================================================
// Machine Inventory Infra Module
//
// Accepts machine definitions from Nix and emits a JSON string output.
// This output is intended to be pulled into stackpanel.infra.outputs.machines
// and consumed by Colmena.
// ==============================================================================
import Infra from "@stackpanel/infra";

interface MachineSshConfig {
  user?: string;
  port?: number;
  keyPath?: string | null;
}

interface MachineDefinition {
  id?: string | null;
  name?: string | null;
  host?: string | null;
  ssh?: MachineSshConfig;
  tags?: string[];
  roles?: string[];
  provider?: string | null;
  arch?: string | null;
  publicIp?: string | null;
  privateIp?: string | null;
  labels?: Record<string, string>;
  nixosProfile?: string | null;
  nixosModules?: string[];
  targetEnv?: string | null;
  env?: Record<string, string>;
  metadata?: Record<string, unknown>;
}

interface MachineInputs {
  source?: "static" | "aws-ec2";
  machines: Record<string, MachineDefinition>;
  aws?: {
    region?: string | null;
    instanceIds?: string[];
    filters?: Array<{ name: string; values: string[] }>;
    nameTagKeys?: string[];
    roleTagKeys?: string[];
    tagKeys?: string[];
    envTagKeys?: string[];
    hostPreference?: Array<"publicDns" | "publicIp" | "privateIp">;
    ssh?: MachineSshConfig;
  };
}

const infra = new Infra("machines");
const inputs = infra.inputs<MachineInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const source = inputs.source ?? "static";
const machines = inputs.machines ?? {};

function tagMap(tags?: Array<{ Key?: string; Value?: string }>): Record<string, string> {
  const result: Record<string, string> = {};
  for (const tag of tags ?? []) {
    if (!tag.Key) continue;
    result[tag.Key] = tag.Value ?? "";
  }
  return result;
}

function pickTagValue(tags: Record<string, string>, keys: string[]): string | null {
  for (const key of keys) {
    const value = tags[key];
    if (value) return value;
  }
  return null;
}

function collectTagValues(tags: Record<string, string>, keys: string[]): string[] {
  const values: string[] = [];
  for (const key of keys) {
    const value = tags[key];
    if (value) values.push(value);
  }
  return values;
}

function pickHost(
  instance: {
    PublicDnsName?: string;
    PublicIpAddress?: string;
    PrivateIpAddress?: string;
  },
  preference: Array<"publicDns" | "publicIp" | "privateIp">,
): string | null {
  for (const pref of preference) {
    if (pref === "publicDns" && instance.PublicDnsName) return instance.PublicDnsName;
    if (pref === "publicIp" && instance.PublicIpAddress) return instance.PublicIpAddress;
    if (pref === "privateIp" && instance.PrivateIpAddress) return instance.PrivateIpAddress;
  }
  return null;
}

function mapArchitecture(arch?: string | null): string | null {
  if (!arch) return null;
  if (arch === "arm64") return "aarch64-linux";
  if (arch === "x86_64") return "x86_64-linux";
  return null;
}

async function loadAwsMachines(awsConfig?: MachineInputs["aws"]): Promise<Record<string, MachineDefinition>> {
  const config = awsConfig ?? {};
  const { EC2Client, DescribeInstancesCommand } = await import("@aws-sdk/client-ec2");

  const region = config.region ?? process.env.AWS_REGION ?? process.env.AWS_DEFAULT_REGION;
  const client = new EC2Client(region ? { region } : {});

  const instanceIds = config.instanceIds ?? [];
  const filters = (config.filters ?? []).map((filter) => ({
    Name: filter.name,
    Values: filter.values,
  }));

  if (instanceIds.length === 0 && filters.length === 0) {
    console.warn("[machines] No instance IDs or filters provided; inventory will be empty.");
    return {};
  }

  const hostPreference = config.hostPreference ?? ["publicDns", "publicIp", "privateIp"];
  const nameTagKeys = config.nameTagKeys ?? ["Name"];
  const roleTagKeys = config.roleTagKeys ?? [];
  const tagKeys = config.tagKeys ?? [];
  const envTagKeys = config.envTagKeys ?? [];
  const defaultSsh = config.ssh ?? { user: "root", port: 22, keyPath: null };

  const inventory: Record<string, MachineDefinition> = {};
  let nextToken: string | undefined;

  do {
    const response = await client.send(
      new DescribeInstancesCommand({
        InstanceIds: instanceIds.length > 0 ? instanceIds : undefined,
        Filters: filters.length > 0 ? filters : undefined,
        NextToken: nextToken,
      }),
    );

    for (const reservation of response.Reservations ?? []) {
      for (const instance of reservation.Instances ?? []) {
        const instanceId = instance.InstanceId ?? "";
        if (!instanceId) continue;

        const tags = tagMap(instance.Tags);
        const name = pickTagValue(tags, nameTagKeys) ?? instanceId;
        const roles = collectTagValues(tags, roleTagKeys);
        const extraTags = collectTagValues(tags, tagKeys);
        const targetEnv = pickTagValue(tags, envTagKeys);
        const host = pickHost(instance, hostPreference);

        inventory[instanceId] = {
          id: instanceId,
          name,
          host,
          ssh: defaultSsh,
          roles,
          tags: extraTags,
          provider: "aws-ec2",
          arch: mapArchitecture(instance.Architecture),
          publicIp: instance.PublicIpAddress ?? null,
          privateIp: instance.PrivateIpAddress ?? null,
          labels: tags,
          targetEnv,
          metadata: {
            availabilityZone: instance.Placement?.AvailabilityZone,
            instanceType: instance.InstanceType,
            state: instance.State?.Name,
          },
        };
      }
    }

    nextToken = response.NextToken;
  } while (nextToken);

  return inventory;
}

const resolvedMachines =
  source === "aws-ec2"
    ? await loadAwsMachines(inputs.aws)
    : machines;

export default {
  machines: JSON.stringify(resolvedMachines),
};
