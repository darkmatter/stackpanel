// ==============================================================================
// AWS EC2 Apps Module
// ==============================================================================
import Infra from "@stackpanel/infra";
import { Ec2Instance } from "@stackpanel/infra/resources/ec2-instance";
import { SecurityGroup } from "@stackpanel/infra/resources/security-group";
import { KeyPair } from "@stackpanel/infra/resources/key-pair";
import { IamRole } from "@stackpanel/infra/resources/iam-role";
import { IamInstanceProfile } from "@stackpanel/infra/resources/iam-instance-profile";

interface SshConfig {
  user?: string;
  port?: number;
  keyPath?: string | null;
}

interface MachineMeta {
  tags?: string[];
  roles?: string[];
  targetEnv?: string | null;
  arch?: string | null;
  ssh?: SshConfig;
}

interface RuleConfig {
  fromPort: number;
  toPort: number;
  protocol?: string;
  cidrBlocks?: string[];
  ipv6CidrBlocks?: string[];
  securityGroupIds?: string[];
  description?: string | null;
}

interface SecurityGroupConfig {
  create?: boolean;
  name?: string | null;
  description?: string | null;
  ingress?: RuleConfig[];
  egress?: RuleConfig[];
  tags?: Record<string, string>;
}

interface KeyPairConfig {
  create?: boolean;
  name?: string | null;
  publicKey?: string | null;
  tags?: Record<string, string>;
  destroyOnDelete?: boolean;
}

interface InlinePolicy {
  name: string;
  document: Record<string, unknown>;
}

interface IamConfig {
  enable?: boolean;
  roleName?: string | null;
  assumeRolePolicy?: Record<string, unknown> | null;
  managedPolicyArns?: string[];
  inlinePolicies?: InlinePolicy[];
  tags?: Record<string, string>;
  instanceProfileName?: string | null;
  instanceProfileTags?: Record<string, string>;
}

interface NixosConfig {
  amiId?: string | null;
  flakeUrl?: string | null;
  hostConfig?: string | null;
  flakeVersion?: string;
}

interface InstanceOverride {
  name?: string | null;
  ami?: string | null;
  osType?: "ubuntu" | "nixos";
  nixos?: NixosConfig;
  instanceType?: string | null;
  subnetId?: string | null;
  securityGroupIds?: string[];
  keyName?: string | null;
  iamInstanceProfile?: string | null;
  userData?: string | null;
  rootVolumeSize?: number | null;
  associatePublicIp?: boolean;
  tags?: Record<string, string>;
  machine?: MachineMeta;
}

interface AppConfig {
  instanceCount?: number;
  instances?: InstanceOverride[];
  ami?: string | null;
  osType?: "ubuntu" | "nixos";
  nixos?: NixosConfig;
  instanceType?: string | null;
  vpcId?: string | null;
  subnetIds?: string[];
  securityGroupIds?: string[];
  securityGroup?: SecurityGroupConfig;
  keyName?: string | null;
  keyPair?: KeyPairConfig;
  iam?: IamConfig;
  iamInstanceProfile?: string | null;
  userData?: string | null;
  rootVolumeSize?: number | null;
  associatePublicIp?: boolean;
  tags?: Record<string, string>;
  machine?: MachineMeta;
}

interface AwsEc2AppInputs {
  defaults?: AppConfig;
  apps: Record<string, AppConfig>;
}

const infra = new Infra("aws-ec2-app");
const inputs = infra.inputs<AwsEc2AppInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const defaults = inputs.defaults ?? {};

const { EC2Client, DescribeVpcsCommand, DescribeSubnetsCommand, DescribeImagesCommand } =
  await import("@aws-sdk/client-ec2");

const region = process.env.AWS_REGION ?? process.env.AWS_DEFAULT_REGION;
const ec2Client = new EC2Client(region ? { region } : {});

async function resolveDefaultNetwork(): Promise<{ vpcId: string; subnetIds: string[] }> {
  const vpcs = await ec2Client.send(
    new DescribeVpcsCommand({
      Filters: [{ Name: "isDefault", Values: ["true"] }],
    }),
  );
  const vpcId = vpcs.Vpcs?.[0]?.VpcId;
  if (!vpcId) {
    throw new Error("aws-ec2-app: unable to resolve default VPC");
  }
  const subnets = await ec2Client.send(
    new DescribeSubnetsCommand({
      Filters: [{ Name: "vpc-id", Values: [vpcId] }],
    }),
  );
  const subnetIds = (subnets.Subnets ?? [])
    .map((subnet) => subnet.SubnetId)
    .filter((id): id is string => Boolean(id));
  if (subnetIds.length === 0) {
    throw new Error("aws-ec2-app: unable to resolve default subnets");
  }
  return { vpcId, subnetIds };
}

function pickList<T>(...lists: Array<T[] | undefined | null>): T[] {
  for (const list of lists) {
    if (list && list.length > 0) return list;
  }
  return [];
}

function mergeTags(...sources: Array<Record<string, string> | undefined>): Record<string, string> {
  const merged: Record<string, string> = {};
  for (const source of sources) {
    if (!source) continue;
    Object.assign(merged, source);
  }
  return merged;
}

function mergeMachineMeta(...sources: Array<MachineMeta | undefined>): MachineMeta {
  const result: MachineMeta = {};
  const tags = new Set<string>();
  const roles = new Set<string>();

  for (const source of sources) {
    if (!source) continue;
    (source.tags ?? []).forEach((tag) => tags.add(tag));
    (source.roles ?? []).forEach((role) => roles.add(role));
    if (source.targetEnv) result.targetEnv = source.targetEnv;
    if (source.arch) result.arch = source.arch;
    if (source.ssh) {
      result.ssh = {
        ...(result.ssh ?? {}),
        ...source.ssh,
      };
    }
  }

  if (tags.size > 0) result.tags = Array.from(tags);
  if (roles.size > 0) result.roles = Array.from(roles);
  return result;
}

async function resolveAmi(
  explicitAmi: string | null | undefined,
  osType: "ubuntu" | "nixos",
  nixos?: NixosConfig,
): Promise<string> {
  if (explicitAmi) return explicitAmi;

  if (osType === "nixos") {
    if (nixos?.amiId) return nixos.amiId;
    const images = await ec2Client.send(
      new DescribeImagesCommand({
        Owners: ["535002876703"],
        Filters: [
          { Name: "name", Values: ["determinate/nixos/epoch-1/*"] },
          { Name: "architecture", Values: ["x86_64"] },
          { Name: "state", Values: ["available"] },
        ],
      }),
    );
    const sorted = (images.Images ?? []).sort((a, b) =>
      (b.CreationDate ?? "").localeCompare(a.CreationDate ?? ""),
    );
    const imageId = sorted[0]?.ImageId;
    if (!imageId) throw new Error("aws-ec2-app: no NixOS AMI found");
    return imageId;
  }

  const images = await ec2Client.send(
    new DescribeImagesCommand({
      Owners: ["099720109477"],
      Filters: [
        {
          Name: "name",
          Values: ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
        },
        { Name: "state", Values: ["available"] },
      ],
    }),
  );
  const sorted = (images.Images ?? []).sort((a, b) =>
    (b.CreationDate ?? "").localeCompare(a.CreationDate ?? ""),
  );
  const imageId = sorted[0]?.ImageId;
  if (!imageId) throw new Error("aws-ec2-app: no Ubuntu AMI found");
  return imageId;
}

function buildNixosUserData(nixos?: NixosConfig): string | null {
  if (!nixos?.flakeUrl || !nixos?.hostConfig) return null;
  const flakeVersion = nixos.flakeVersion ?? "*";
  return `#!/usr/bin/env bash
set -euo pipefail
exec >> /var/log/user-data.log 2>&1

echo "[+] Authenticating with FlakeHub using AWS STS..."
determinate-nixd login aws

echo "[+] Applying NixOS configuration: ${nixos.flakeUrl}/${flakeVersion}#nixosConfigurations.${nixos.hostConfig}"
fh apply nixos "${nixos.flakeUrl}/${flakeVersion}#nixosConfigurations.${nixos.hostConfig}"

echo "[+] NixOS configuration applied successfully"
`;
}

const defaultNetwork = await resolveDefaultNetwork();

const instanceIds: Record<string, string> = {};
const publicIps: Record<string, string> = {};
const privateIps: Record<string, string> = {};
const publicDns: Record<string, string> = {};
const machines: Record<string, Record<string, unknown>> = {};

for (const [appName, appConfig] of Object.entries(inputs.apps ?? {})) {
  const appSecurityGroup = { ...defaults.securityGroup, ...appConfig.securityGroup };
  const appKeyPair = { ...defaults.keyPair, ...appConfig.keyPair };
  const appIam = { ...defaults.iam, ...appConfig.iam };

  const vpcId = appConfig.vpcId ?? defaults.vpcId ?? defaultNetwork.vpcId;
  const subnetIds = pickList(appConfig.subnetIds, defaults.subnetIds, defaultNetwork.subnetIds);
  if (subnetIds.length === 0) {
    throw new Error(`aws-ec2-app: no subnet IDs available for ${appName}`);
  }

  let securityGroupIds = pickList(appConfig.securityGroupIds, defaults.securityGroupIds);
  if (appSecurityGroup?.create) {
    const sgName = appSecurityGroup.name ?? `${appName}-sg`;
    const sg = await SecurityGroup(infra.id(`${appName}-sg`), {
      name: sgName,
      description: appSecurityGroup.description ?? sgName,
      vpcId,
      ingress: appSecurityGroup.ingress ?? [],
      egress:
        (appSecurityGroup.egress ?? []).length > 0
          ? appSecurityGroup.egress
          : [
              {
                fromPort: 0,
                toPort: 0,
                protocol: "-1",
                cidrBlocks: ["0.0.0.0/0"],
                ipv6CidrBlocks: ["::/0"],
              },
            ],
      tags: mergeTags(defaults.tags, appConfig.tags, appSecurityGroup.tags),
    });
    securityGroupIds = [sg.groupId];
  }

  let keyName = appConfig.keyName ?? defaults.keyName ?? null;
  if (appKeyPair?.create) {
    if (!appKeyPair.name || !appKeyPair.publicKey) {
      throw new Error(`aws-ec2-app: key pair name and public key required for ${appName}`);
    }
    const keyPair = await KeyPair(infra.id(`${appName}-key`), {
      keyName: appKeyPair.name,
      publicKey: appKeyPair.publicKey,
      tags: appKeyPair.tags,
      destroyOnDelete: appKeyPair.destroyOnDelete,
    });
    keyName = keyPair.keyName;
  }

  let iamInstanceProfile = appConfig.iamInstanceProfile ?? defaults.iamInstanceProfile ?? null;
  if (appIam?.enable) {
    const roleName = appIam.roleName ?? `${appName}-role`;
    const role = await IamRole(infra.id(`${appName}-role`), {
      roleName,
      assumeRolePolicy: appIam.assumeRolePolicy ?? {
        Version: "2012-10-17",
        Statement: [
          {
            Effect: "Allow",
            Principal: { Service: "ec2.amazonaws.com" },
            Action: "sts:AssumeRole",
          },
        ],
      },
      description: `EC2 role for ${appName}`,
      tags: appIam.tags,
      managedPolicyArns: appIam.managedPolicyArns,
      policies: (appIam.inlinePolicies ?? []).map((policy) => ({
        policyName: policy.name,
        policyDocument: policy.document,
      })),
    });

    const profileName = appIam.instanceProfileName ?? `${roleName}-profile`;
    const profile = await IamInstanceProfile(infra.id(`${appName}-profile`), {
      name: profileName,
      roleName: role.roleName,
      tags: appIam.instanceProfileTags,
    });
    iamInstanceProfile = profile.name;
  }

  const instanceList =
    (appConfig.instances ?? []).length > 0
      ? appConfig.instances ?? []
      : Array.from({ length: appConfig.instanceCount ?? 1 }, () => ({} as InstanceOverride));

  let index = 0;
  for (const instance of instanceList) {
    const instanceName =
      instance.name ?? `${appName}-${index + 1}`;
    const osType = instance.osType ?? appConfig.osType ?? defaults.osType ?? "ubuntu";
    const nixosConfig = { ...defaults.nixos, ...appConfig.nixos, ...instance.nixos };

    const ami = await resolveAmi(
      instance.ami ?? appConfig.ami ?? defaults.ami,
      osType,
      nixosConfig,
    );

    const subnetId = instance.subnetId ?? subnetIds[index % subnetIds.length];
    const securityGroups = pickList(instance.securityGroupIds, securityGroupIds);

    const userData =
      instance.userData ??
      appConfig.userData ??
      defaults.userData ??
      (osType === "nixos" ? buildNixosUserData(nixosConfig) : null);

    const instanceTags = mergeTags(
      defaults.tags,
      appConfig.tags,
      instance.tags,
      {
        Name: instanceName,
        Service: appName,
        OSType: osType,
      },
    );
    if (osType === "nixos" && nixosConfig.hostConfig) {
      instanceTags.NixOSHostConfig = nixosConfig.hostConfig;
    }
    if (osType === "nixos" && nixosConfig.flakeUrl) {
      instanceTags.NixOSFlakeURL = nixosConfig.flakeUrl;
    }

    const resource = await Ec2Instance(infra.id(instanceName), {
      name: instanceName,
      ami,
      instanceType:
        instance.instanceType ??
        appConfig.instanceType ??
        defaults.instanceType ??
        "t3.micro",
      subnetId,
      securityGroupIds: securityGroups,
      keyName: instance.keyName ?? appConfig.keyName ?? keyName ?? null,
      iamInstanceProfile: instance.iamInstanceProfile ?? iamInstanceProfile ?? null,
      userData,
      rootVolumeSize:
        instance.rootVolumeSize ?? appConfig.rootVolumeSize ?? defaults.rootVolumeSize ?? null,
      associatePublicIp:
        instance.associatePublicIp ?? appConfig.associatePublicIp ?? defaults.associatePublicIp ?? true,
      tags: instanceTags,
    });

    instanceIds[instanceName] = resource.instanceId;
    if (resource.publicIp) publicIps[instanceName] = resource.publicIp;
    if (resource.privateIp) privateIps[instanceName] = resource.privateIp;
    if (resource.publicDns) publicDns[instanceName] = resource.publicDns;

    const machineMeta = mergeMachineMeta(defaults.machine, appConfig.machine, instance.machine);
    const host = resource.publicDns ?? resource.publicIp ?? resource.privateIp ?? null;

    machines[instanceName] = {
      id: resource.instanceId,
      name: instanceName,
      host,
      ssh: {
        user: machineMeta.ssh?.user ?? "root",
        port: machineMeta.ssh?.port ?? 22,
        keyPath: machineMeta.ssh?.keyPath ?? null,
      },
      tags: machineMeta.tags ?? [],
      roles: machineMeta.roles ?? [],
      targetEnv: machineMeta.targetEnv ?? null,
      arch: machineMeta.arch ?? null,
      provider: "aws-ec2",
      publicIp: resource.publicIp ?? null,
      privateIp: resource.privateIp ?? null,
      labels: instanceTags,
      metadata: {
        subnetId,
        instanceType:
          instance.instanceType ?? appConfig.instanceType ?? defaults.instanceType ?? "t3.micro",
      },
    };

    index += 1;
  }
}

export default {
  instanceIds: JSON.stringify(instanceIds),
  publicIps: JSON.stringify(publicIps),
  privateIps: JSON.stringify(privateIps),
  publicDns: JSON.stringify(publicDns),
  machines: JSON.stringify(machines),
};
