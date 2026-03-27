// ==============================================================================
// AWS EC2 Instances Module
// ==============================================================================
import Infra from "@stackpanel/infra";
import { Ec2Instance } from "@stackpanel/infra/resources/ec2-instance";

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

interface InstanceInput {
  name: string;
  ami: string;
  instanceType?: string;
  subnetId?: string;
  securityGroupIds?: string[];
  keyName?: string | null;
  iamInstanceProfile?: string | null;
  userData?: string | null;
  rootVolumeSize?: number | null;
  associatePublicIp?: boolean;
  tags?: Record<string, string>;
  machine?: MachineMeta;
}

interface AwsEc2Inputs {
  defaults?: InstanceInput;
  instances: InstanceInput[];
}

const infra = new Infra("aws-ec2");
const inputs = infra.inputs<AwsEc2Inputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const defaults = inputs.defaults ?? ({} as InstanceInput);
const resolvedInstances = inputs.instances ?? [];

const instanceIds: string[] = [];
const publicIps: string[] = [];
const privateIps: string[] = [];
const publicDns: string[] = [];
const machines: Record<string, Record<string, unknown>> = {};

for (const instance of resolvedInstances) {
  const resolved: InstanceInput = {
    ...defaults,
    ...instance,
    tags: { ...(defaults.tags ?? {}), ...(instance.tags ?? {}) },
    machine: {
      ...(defaults.machine ?? {}),
      ...(instance.machine ?? {}),
      ssh: { ...(defaults.machine?.ssh ?? {}), ...(instance.machine?.ssh ?? {}) },
    },
  };

  const associatePublicIp = resolved.associatePublicIp ?? true;
  if (!resolved.subnetId) {
    throw new Error(`EC2 instance "${resolved.name}" is missing required subnetId`);
  }

  const resource = await Ec2Instance(infra.id(resolved.name), {
    name: resolved.name,
    ami: resolved.ami,
    instanceType: resolved.instanceType ?? "t3.micro",
    subnetId: resolved.subnetId,
    securityGroupIds: resolved.securityGroupIds ?? [],
    keyName: resolved.keyName ?? undefined,
    iamInstanceProfile: resolved.iamInstanceProfile ?? undefined,
    userData: resolved.userData ?? undefined,
    rootVolumeSize: resolved.rootVolumeSize ?? undefined,
    associatePublicIp,
    tags: resolved.tags ?? {},
  });

  instanceIds.push(resource.instanceId);
  if (resource.publicIp) publicIps.push(resource.publicIp);
  if (resource.privateIp) privateIps.push(resource.privateIp);
  if (resource.publicDns) publicDns.push(resource.publicDns);

  const host = resource.publicDns ?? resource.publicIp ?? resource.privateIp ?? null;

  machines[resolved.name] = {
    id: resource.instanceId,
    name: resolved.name,
    host,
    ssh: {
      user: resolved.machine?.ssh?.user ?? "root",
      port: resolved.machine?.ssh?.port ?? 22,
      keyPath: resolved.machine?.ssh?.keyPath ?? null,
    },
    tags: resolved.machine?.tags ?? [],
    roles: resolved.machine?.roles ?? [],
    targetEnv: resolved.machine?.targetEnv ?? null,
    arch: resolved.machine?.arch ?? null,
    provider: "aws-ec2",
    publicIp: resource.publicIp ?? null,
    privateIp: resource.privateIp ?? null,
    labels: resolved.tags ?? {},
    metadata: {
      instanceType: resolved.instanceType ?? "t3.micro",
      subnetId: resolved.subnetId ?? null,
    },
  };
}

export default {
  instanceIds: JSON.stringify(instanceIds),
  publicIps: JSON.stringify(publicIps),
  privateIps: JSON.stringify(privateIps),
  publicDns: JSON.stringify(publicDns),
  machines: JSON.stringify(machines),
};
