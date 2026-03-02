// ==============================================================================
// AWS EC2 Apps Module
//
// High-level app-centric EC2 provisioning with optional:
//   - Security group creation
//   - Key pair import
//   - IAM role + instance profile
//   - ALB + target group + listeners + host-based routing
//   - ECR repository + GitHub OIDC push role
//   - SSM parameter wiring (env file generation)
//   - Machine inventory for Colmena
// ==============================================================================
import Infra from "@stackpanel/infra";
import { Ec2Instance } from "@stackpanel/infra/resources/ec2-instance";
import { SecurityGroup } from "@stackpanel/infra/resources/security-group";
import { KeyPair } from "@stackpanel/infra/resources/key-pair";
import { IamRole } from "@stackpanel/infra/resources/iam-role";
import { IamInstanceProfile } from "@stackpanel/infra/resources/iam-instance-profile";
import { ApplicationLoadBalancer } from "@stackpanel/infra/resources/application-load-balancer";
import { TargetGroup } from "@stackpanel/infra/resources/target-group";
import { Listener } from "@stackpanel/infra/resources/listener";
import { ListenerRule } from "@stackpanel/infra/resources/listener-rule";
import { TargetGroupAttachment } from "@stackpanel/infra/resources/target-group-attachment";
import { EcrRepository } from "@stackpanel/infra/resources/ecr-repository";

// =============================================================================
// Types
// =============================================================================

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

interface AlbHealthCheck {
  enabled?: boolean;
  path?: string;
  protocol?: "HTTP" | "HTTPS" | "TCP";
  port?: string | null;
  interval?: number;
  timeout?: number;
  healthyThreshold?: number;
  unhealthyThreshold?: number;
  matcher?: string;
}

interface AlbTargetGroupConfig {
  port?: number;
  protocol?: "HTTP" | "HTTPS" | "TCP";
  healthCheck?: AlbHealthCheck;
}

interface AlbConfig {
  enable?: boolean;
  create?: boolean;
  name?: string | null;
  scheme?: "internet-facing" | "internal";
  ipAddressType?: "ipv4" | "dualstack";
  subnetIds?: string[];
  securityGroupIds?: string[];
  http?: boolean;
  https?: boolean;
  certificateArn?: string | null;
  sslPolicy?: string;
  existingListenerHttpArn?: string | null;
  existingListenerHttpsArn?: string | null;
  hostnames?: string[];
  hostRulePriority?: number;
  targetGroup?: AlbTargetGroupConfig;
}

interface GithubOidcConfig {
  enable?: boolean;
  repoOwner?: string | null;
  repoName?: string | null;
  allowedBranches?: string[];
  allowedWorkflows?: string[];
  allowTags?: boolean;
  roleName?: string | null;
  oidcProviderArn?: string | null;
  createOidcProvider?: boolean;
}

interface EcrConfig {
  enable?: boolean;
  create?: boolean;
  repoName?: string | null;
  imageTagMutability?: "MUTABLE" | "IMMUTABLE";
  scanOnPush?: boolean;
  lifecyclePolicy?: string | null;
  github?: GithubOidcConfig;
}

interface SsmConfig {
  enable?: boolean;
  region?: string | null;
  pathPrefix?: string | null;
  parameters?: Record<string, string>;
  secureParameters?: Record<string, string>;
  envFilePath?: string | null;
  refreshScriptPath?: string | null;
  installCli?: boolean;
  useChamber?: boolean;
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
  alb?: AlbConfig;
  ecr?: EcrConfig;
  ssm?: SsmConfig;
  machine?: MachineMeta;
}

interface AwsEc2AppInputs {
  defaults?: AppConfig;
  apps: Record<string, AppConfig>;
}

// =============================================================================
// Init
// =============================================================================

const infra = new Infra("aws-ec2-app");
const inputs = infra.inputs<AwsEc2AppInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const defaults = inputs.defaults ?? {};

const { EC2Client, DescribeVpcsCommand, DescribeSubnetsCommand, DescribeImagesCommand } =
  await import("@aws-sdk/client-ec2");

const awsRegion = process.env.AWS_REGION ?? process.env.AWS_DEFAULT_REGION;
const ec2Client = new EC2Client(awsRegion ? { region: awsRegion } : {});

// =============================================================================
// Helpers
// =============================================================================

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
          Values: ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"],
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

async function getAccountId(): Promise<string> {
  const { STSClient, GetCallerIdentityCommand } = await import("@aws-sdk/client-sts");
  const client = new STSClient(awsRegion ? { region: awsRegion } : {});
  const identity = await client.send(new GetCallerIdentityCommand({}));
  return identity.Account!;
}

// =============================================================================
// Resolve network
// =============================================================================

const defaultNetwork = await resolveDefaultNetwork();

// =============================================================================
// Outputs
// =============================================================================

const instanceIds: Record<string, string> = {};
const publicIps: Record<string, string> = {};
const privateIps: Record<string, string> = {};
const publicDns: Record<string, string> = {};
const machines: Record<string, Record<string, unknown>> = {};
const albOutputs: Record<string, Record<string, unknown>> = {};
const ecrOutputs: Record<string, Record<string, unknown>> = {};
const ssmOutputs: Record<string, Record<string, unknown>> = {};

// =============================================================================
// Per-app loop
// =============================================================================

for (const [appName, appConfig] of Object.entries(inputs.apps ?? {})) {
  const appSecurityGroup = { ...defaults.securityGroup, ...appConfig.securityGroup };
  const appKeyPair = { ...defaults.keyPair, ...appConfig.keyPair };
  const appIam = { ...defaults.iam, ...appConfig.iam };
  const appAlb = { ...defaults.alb, ...appConfig.alb };
  const appEcr = { ...defaults.ecr, ...appConfig.ecr };
  const appSsm = { ...defaults.ssm, ...appConfig.ssm };

  const vpcId = appConfig.vpcId ?? defaults.vpcId ?? defaultNetwork.vpcId;
  const subnetIds = pickList(appConfig.subnetIds, defaults.subnetIds, defaultNetwork.subnetIds);
  if (subnetIds.length === 0) {
    throw new Error(`aws-ec2-app: no subnet IDs available for ${appName}`);
  }

  // ---------------------------------------------------------------------------
  // Security group
  // ---------------------------------------------------------------------------
  let securityGroupIds = pickList(appConfig.securityGroupIds, defaults.securityGroupIds);
  let appSgGroupId: string | undefined;
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
    appSgGroupId = sg.groupId;
    securityGroupIds = [sg.groupId];
  }

  // ---------------------------------------------------------------------------
  // Key pair
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // IAM role + instance profile
  // ---------------------------------------------------------------------------
  let iamInstanceProfile = appConfig.iamInstanceProfile ?? defaults.iamInstanceProfile ?? null;
  let iamRoleArn: string | undefined;
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
    iamRoleArn = role.arn;

    const profileName = appIam.instanceProfileName ?? `${roleName}-profile`;
    const profile = await IamInstanceProfile(infra.id(`${appName}-profile`), {
      name: profileName,
      roleName: role.roleName,
      tags: appIam.instanceProfileTags,
    });
    iamInstanceProfile = profile.name;
  }

  // ---------------------------------------------------------------------------
  // SSM parameters
  // ---------------------------------------------------------------------------
  if (appSsm?.enable) {
    const { SSMClient, PutParameterCommand } = await import("@aws-sdk/client-ssm");
    const ssmClient = new SSMClient(
      appSsm.region ? { region: appSsm.region } : awsRegion ? { region: awsRegion } : {},
    );

    const prefix = appSsm.pathPrefix ?? `/${appName}`;
    const allParams = {
      ...(appSsm.parameters ?? {}),
      ...(appSsm.secureParameters ?? {}),
    };
    const secureKeys = new Set(Object.keys(appSsm.secureParameters ?? {}));

    for (const [key, value] of Object.entries(allParams)) {
      const paramName = `${prefix}/${key}`;
      await ssmClient.send(
        new PutParameterCommand({
          Name: paramName,
          Value: value,
          Type: secureKeys.has(key) ? "SecureString" : "String",
          Overwrite: true,
        }),
      );
    }

    ssmOutputs[appName] = {
      pathPrefix: prefix,
      parameterCount: Object.keys(allParams).length,
      envFilePath: appSsm.envFilePath ?? `/etc/default/${appName}.env`,
    };
  }

  // ---------------------------------------------------------------------------
  // ECR repository
  // ---------------------------------------------------------------------------
  let ecrRepoUrl: string | undefined;
  if (appEcr?.enable) {
    const repoName = appEcr.repoName ?? appName;
    if (appEcr.create !== false) {
      const defaultLifecyclePolicy = JSON.stringify({
        rules: [
          {
            rulePriority: 1,
            description: "Keep last 50 images",
            selection: {
              tagStatus: "any",
              countType: "imageCountMoreThan",
              countNumber: 50,
            },
            action: { type: "expire" },
          },
        ],
      });
      const repo = await EcrRepository(infra.id(`${appName}-ecr`), {
        name: repoName,
        imageTagMutability: appEcr.imageTagMutability,
        scanOnPush: appEcr.scanOnPush,
        lifecyclePolicy: appEcr.lifecyclePolicy ?? defaultLifecyclePolicy,
        tags: mergeTags(defaults.tags, appConfig.tags),
      });
      ecrRepoUrl = repo.repositoryUrl;

      ecrOutputs[appName] = {
        repositoryUrl: repo.repositoryUrl,
        repositoryArn: repo.arn,
        repositoryName: repo.name,
      };
    }

    // GitHub OIDC role for ECR push
    const github = appEcr.github;
    if (github?.enable) {
      const accountId = await getAccountId();
      let oidcProviderArn = github.oidcProviderArn ?? null;

      if (!oidcProviderArn && github.createOidcProvider) {
        const { GitHubOIDCProvider } = await import("alchemy/aws/oidc");
        const oidc = await GitHubOIDCProvider(infra.id(`${appName}-oidc`), {});
        oidcProviderArn = oidc.arn;
      }

      if (oidcProviderArn && github.repoOwner && github.repoName) {
        const branchSubjects = (github.allowedBranches ?? []).map(
          (b) => `repo:${github.repoOwner}/${github.repoName}:ref:refs/heads/${b}`,
        );
        const tagSubjects = github.allowTags
          ? [`repo:${github.repoOwner}/${github.repoName}:ref:refs/tags/*`]
          : [];
        const workflowSubjects = (github.allowedWorkflows ?? []).map(
          (w) => `repo:${github.repoOwner}/${github.repoName}:workflow:${w}`,
        );
        const allSubjects = [...branchSubjects, ...tagSubjects, ...workflowSubjects];
        if (allSubjects.length === 0) {
          allSubjects.push(`repo:${github.repoOwner}/${github.repoName}:*`);
        }

        const ghaRoleName = github.roleName ?? `${appName}-gha-ecr-push`;
        const ecrRepoArn = `arn:aws:ecr:${awsRegion ?? "us-east-1"}:${accountId}:repository/${appEcr.repoName ?? appName}`;

        const ssmPrefix = appSsm?.pathPrefix ?? `/${appName}`;

        await IamRole(infra.id(`${appName}-gha-role`), {
          roleName: ghaRoleName,
          assumeRolePolicy: {
            Version: "2012-10-17",
            Statement: [
              {
                Sid: "GitHubActionsFederatedOIDC",
                Effect: "Allow",
                Principal: { Federated: oidcProviderArn },
                Action: "sts:AssumeRoleWithWebIdentity",
                Condition: {
                  StringLike: {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
                    "token.actions.githubusercontent.com:sub": allSubjects,
                  },
                },
              },
              {
                Sid: "AllowRoot",
                Effect: "Allow",
                Principal: { AWS: `arn:aws:iam::${accountId}:root` },
                Action: "sts:AssumeRole",
              },
            ],
          },
          description: `GitHub Actions role for ${appName} ECR push`,
          tags: mergeTags(defaults.tags, appConfig.tags),
          policies: [
            {
              policyName: `${ghaRoleName}-ecr`,
              policyDocument: {
                Version: "2012-10-17",
                Statement: [
                  {
                    Sid: "ECRAuth",
                    Effect: "Allow",
                    Action: ["ecr:GetAuthorizationToken"],
                    Resource: "*",
                  },
                  {
                    Sid: "ECRPushPull",
                    Effect: "Allow",
                    Action: [
                      "ecr:BatchCheckLayerAvailability",
                      "ecr:BatchGetImage",
                      "ecr:CompleteLayerUpload",
                      "ecr:InitiateLayerUpload",
                      "ecr:PutImage",
                      "ecr:UploadLayerPart",
                      "ecr:DescribeImages",
                      "ecr:GetDownloadUrlForLayer",
                      "ecr:ListImages",
                    ],
                    Resource: [ecrRepoArn],
                  },
                  {
                    Sid: "SSMAccess",
                    Effect: "Allow",
                    Action: [
                      "ssm:GetParameter",
                      "ssm:GetParameters",
                      "ssm:GetParametersByPath",
                      "ssm:PutParameter",
                      "ssm:DeleteParameter",
                      "ssm:DescribeParameters",
                    ],
                    Resource: [
                      `arn:aws:ssm:${awsRegion ?? "*"}:${accountId}:parameter${ssmPrefix}/*`,
                    ],
                  },
                  {
                    Sid: "SSMSendCommand",
                    Effect: "Allow",
                    Action: [
                      "ssm:SendCommand",
                      "ssm:ListCommandInvocations",
                      "ssm:GetCommandInvocation",
                    ],
                    Resource: [
                      `arn:aws:ssm:*:*:document/AWS-RunShellScript`,
                      `arn:aws:ec2:*:${accountId}:instance/*`,
                    ],
                  },
                  {
                    Sid: "ECRCreateRepo",
                    Effect: "Allow",
                    Action: [
                      "ecr:CreateRepository",
                      "ecr:DescribeRepositories",
                    ],
                    Resource: "*",
                  },
                ],
              },
            },
          ],
        });

        ecrOutputs[appName] = {
          ...(ecrOutputs[appName] ?? {}),
          ghaRoleName,
        };
      }
    }
  }

  // ---------------------------------------------------------------------------
  // EC2 instances
  // ---------------------------------------------------------------------------
  const instanceList =
    (appConfig.instances ?? []).length > 0
      ? appConfig.instances ?? []
      : Array.from({ length: appConfig.instanceCount ?? 1 }, () => ({} as InstanceOverride));

  const appInstanceIds: string[] = [];

  let index = 0;
  for (const instance of instanceList) {
    const instanceName = instance.name ?? `${appName}-${index + 1}`;
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

    const instanceTags = mergeTags(defaults.tags, appConfig.tags, instance.tags, {
      Name: instanceName,
      Service: appName,
      OSType: osType,
    });
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
        instance.instanceType ?? appConfig.instanceType ?? defaults.instanceType ?? "t3.micro",
      subnetId,
      securityGroupIds: securityGroups,
      keyName: instance.keyName ?? appConfig.keyName ?? keyName ?? null,
      iamInstanceProfile: instance.iamInstanceProfile ?? iamInstanceProfile ?? null,
      userData,
      rootVolumeSize:
        instance.rootVolumeSize ?? appConfig.rootVolumeSize ?? defaults.rootVolumeSize ?? null,
      associatePublicIp:
        instance.associatePublicIp ??
        appConfig.associatePublicIp ??
        defaults.associatePublicIp ??
        true,
      tags: instanceTags,
    });

    appInstanceIds.push(resource.instanceId);
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

  // ---------------------------------------------------------------------------
  // ALB + target group + listeners + host rules
  // ---------------------------------------------------------------------------
  if (appAlb?.enable && appInstanceIds.length > 0) {
    const tgPort = appAlb.targetGroup?.port ?? 80;
    const tgProtocol = appAlb.targetGroup?.protocol ?? "HTTP";
    const tgHealthCheck = appAlb.targetGroup?.healthCheck ?? {};

    const tgName = `${appName}-tg`.substring(0, 32).replace(/[^a-zA-Z0-9-]/g, "-");
    const tg = await TargetGroup(infra.id(`${appName}-tg`), {
      name: tgName,
      port: tgPort,
      protocol: tgProtocol,
      vpcId,
      healthCheck: {
        enabled: tgHealthCheck.enabled ?? true,
        protocol: tgHealthCheck.protocol ?? "HTTP",
        port: tgHealthCheck.port ?? undefined,
        path: tgHealthCheck.path ?? "/",
        interval: tgHealthCheck.interval ?? 30,
        timeout: tgHealthCheck.timeout ?? 10,
        healthyThreshold: tgHealthCheck.healthyThreshold ?? 2,
        unhealthyThreshold: tgHealthCheck.unhealthyThreshold ?? 3,
        matcher: tgHealthCheck.matcher ?? "200-399",
      },
      tags: mergeTags(defaults.tags, appConfig.tags),
    });

    // Register instances
    for (const instanceId of appInstanceIds) {
      await TargetGroupAttachment(infra.id(`${appName}-tga-${instanceId}`), {
        targetGroupArn: tg.arn,
        targetId: instanceId,
        port: tgPort,
      });
    }

    let httpListenerArn: string | undefined;
    let httpsListenerArn: string | undefined;

    if (appAlb.create !== false) {
      // Create ALB + ALB SG
      const albSgName = appAlb.name
        ? `${appAlb.name}-alb-sg`
        : `${appName}-alb-sg`;
      const albSg = await SecurityGroup(infra.id(`${appName}-alb-sg`), {
        name: albSgName,
        description: `ALB security group for ${appName}`,
        vpcId,
        ingress: [
          {
            fromPort: 80,
            toPort: 80,
            protocol: "tcp",
            cidrBlocks: ["0.0.0.0/0"],
            ipv6CidrBlocks: ["::/0"],
            description: "HTTP",
          },
          {
            fromPort: 443,
            toPort: 443,
            protocol: "tcp",
            cidrBlocks: ["0.0.0.0/0"],
            ipv6CidrBlocks: ["::/0"],
            description: "HTTPS",
          },
        ],
        egress: [
          {
            fromPort: 0,
            toPort: 0,
            protocol: "-1",
            cidrBlocks: ["0.0.0.0/0"],
            ipv6CidrBlocks: ["::/0"],
          },
        ],
        tags: mergeTags(defaults.tags, appConfig.tags, { Name: albSgName }),
      });

      const albName =
        (appAlb.name ?? `${appName}-alb`).substring(0, 32).replace(/[^a-zA-Z0-9-]/g, "-");
      const alb = await ApplicationLoadBalancer(infra.id(`${appName}-alb`), {
        name: albName,
        subnets: pickList(appAlb.subnetIds, subnetIds),
        securityGroupIds: pickList(appAlb.securityGroupIds, [albSg.groupId]),
        scheme: appAlb.scheme ?? "internet-facing",
        ipAddressType: appAlb.ipAddressType ?? "ipv4",
        tags: mergeTags(defaults.tags, appConfig.tags),
      });

      if (appAlb.http !== false) {
        const httpListener = await Listener(infra.id(`${appName}-http`), {
          loadBalancerArn: alb.arn,
          port: 80,
          protocol: "HTTP",
          defaultTargetGroupArn: tg.arn,
        });
        httpListenerArn = httpListener.arn;
      }

      if (appAlb.https && appAlb.certificateArn) {
        const httpsListener = await Listener(infra.id(`${appName}-https`), {
          loadBalancerArn: alb.arn,
          port: 443,
          protocol: "HTTPS",
          sslPolicy: appAlb.sslPolicy ?? "ELBSecurityPolicy-TLS13-1-2-2021-06",
          certificateArn: appAlb.certificateArn,
          defaultTargetGroupArn: tg.arn,
        });
        httpsListenerArn = httpsListener.arn;
      }

      albOutputs[appName] = {
        albArn: alb.arn,
        albDnsName: alb.dnsName,
        albZoneId: alb.zoneId,
        targetGroupArn: tg.arn,
        httpListenerArn: httpListenerArn ?? null,
        httpsListenerArn: httpsListenerArn ?? null,
      };
    } else {
      // Use existing shared listeners
      httpListenerArn = appAlb.existingListenerHttpArn ?? undefined;
      httpsListenerArn = appAlb.existingListenerHttpsArn ?? undefined;

      albOutputs[appName] = {
        targetGroupArn: tg.arn,
        httpListenerArn: httpListenerArn ?? null,
        httpsListenerArn: httpsListenerArn ?? null,
      };
    }

    // Host-based routing rules
    const hostnames = appAlb.hostnames ?? [];
    if (hostnames.length > 0) {
      const listenerArn = httpsListenerArn ?? httpListenerArn;
      if (listenerArn) {
        const priority = appAlb.hostRulePriority ?? 100;
        await ListenerRule(infra.id(`${appName}-host-rule`), {
          listenerArn,
          priority,
          hostnames,
          targetGroupArn: tg.arn,
        });
      }
    }
  }
}

// =============================================================================
// Export
// =============================================================================

export default {
  instanceIds: JSON.stringify(instanceIds),
  publicIps: JSON.stringify(publicIps),
  privateIps: JSON.stringify(privateIps),
  publicDns: JSON.stringify(publicDns),
  machines: JSON.stringify(machines),
  albOutputs: JSON.stringify(albOutputs),
  ecrOutputs: JSON.stringify(ecrOutputs),
  ssmOutputs: JSON.stringify(ssmOutputs),
};
