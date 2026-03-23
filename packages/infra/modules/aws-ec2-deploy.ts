import { isSecret, type Secret } from "alchemy";
import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";
import {
  InternetGateway,
  InternetGatewayAttachment,
  Role,
  Route,
  RouteTable,
  RouteTableAssociation,
  SecurityGroup,
  SecurityGroupRule,
  SSMParameter,
  Subnet,
  Vpc,
} from "alchemy/aws";
import AWS from "alchemy/aws/control";

const DEFAULT_IMAGE_ID =
  "{{resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64}}";

type EnvironmentValue = string | Secret<string>;

export interface Ec2ServerProps {
  appName: string;
  parameterPath: string;
  artifactBucket: string;
  artifactKey: string;
  artifactVersion?: string;
  environment: Record<string, EnvironmentValue>;
  region?: string;
  availabilityZone?: string | null;
  imageId?: string | null;
  instanceType?: string | null;
  keyName?: string | null;
  port?: number | null;
  httpCidrBlocks?: string[];
  sshCidrBlocks?: string[];
  vpcCidrBlock?: string | null;
  subnetCidrBlock?: string | null;
  rootVolumeSize?: number | null;
  tags?: Record<string, string>;
}

export interface Ec2Server extends Ec2ServerProps {
  instanceId: string;
  publicIp: string;
  publicDnsName: string;
  url: string;
  vpcId: string;
  subnetId: string;
  securityGroupId: string;
  roleArn: string;
  instanceProfileArn: string;
}

export interface RuntimeLayout {
  slug: string;
  serviceName: string;
  appRoot: string;
  releaseRoot: string;
  envFile: string;
  archivePath: string;
}

export function deriveRuntimeLayout(appName: string): RuntimeLayout {
  const slug = sanitizeName(appName);
  const baseName = `stackpanel-${slug}`;

  return {
    slug,
    serviceName: `${baseName}.service`,
    appRoot: `/opt/${baseName}`,
    releaseRoot: `/opt/${baseName}/release`,
    envFile: `/etc/${baseName}.env`,
    archivePath: `/tmp/${baseName}-release.tar.gz`,
  };
}

export async function Ec2Server(
  id: string,
  props: Ec2ServerProps,
): Promise<Ec2Server> {
  const region = props.region ?? "us-west-2";
  const availabilityZone = props.availabilityZone ?? `${region}a`;
  const imageId = await resolveImageId(props.imageId ?? DEFAULT_IMAGE_ID, region);
  const instanceType = props.instanceType ?? "t3.small";
  const port = props.port ?? 80;
  const httpCidrBlocks = props.httpCidrBlocks ?? ["0.0.0.0/0"];
  const sshCidrBlocks = props.sshCidrBlocks ?? [];
  const vpcCidrBlock = props.vpcCidrBlock ?? "10.42.0.0/16";
  const subnetCidrBlock = props.subnetCidrBlock ?? "10.42.1.0/24";
  const rootVolumeSize = props.rootVolumeSize ?? 20;
  const namePrefix = props.tags?.Stage ? `${id}-${props.tags.Stage}` : id;
  const layout = deriveRuntimeLayout(props.appName);
  const tags = {
    Name: id,
    ManagedBy: "alchemy",
    Service: props.appName,
    ...props.tags,
  };

  const role = await Role(`${id}-instance-role`, {
    roleName: `${namePrefix}-instance-role`,
    assumeRolePolicy: {
      Version: "2012-10-17",
      Statement: [
        {
          Effect: "Allow",
          Principal: {
            Service: "ec2.amazonaws.com",
          },
          Action: "sts:AssumeRole",
        },
      ],
    },
    description: `Allows the EC2 instance for ${props.appName} to read boot-time config and artifacts.`,
    managedPolicyArns: [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ],
    policies: [
      {
        policyName: `${id}-read-config`,
        policyDocument: {
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Action: [
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath",
              ],
              Resource: [
                `arn:aws:ssm:${region}:*:parameter${props.parameterPath}`,
                `arn:aws:ssm:${region}:*:parameter${props.parameterPath}/*`,
              ],
            },
            {
              Effect: "Allow",
              Action: ["s3:GetBucketLocation", "s3:ListBucket"],
              Resource: [`arn:aws:s3:::${props.artifactBucket}`],
              Condition: {
                StringLike: {
                  "s3:prefix": [props.artifactKey],
                },
              },
            },
            {
              Effect: "Allow",
              Action: ["s3:GetObject"],
              Resource: [
                `arn:aws:s3:::${props.artifactBucket}/${props.artifactKey}`,
              ],
            },
            {
              Effect: "Allow",
              Action: ["kms:Decrypt"],
              Resource: "*",
            },
          ],
        },
      },
    ],
    tags,
  });

  const instanceProfileName = `${namePrefix}-instance-profile`;
  const instanceProfile = await AWS.IAM.InstanceProfile(
    `${id}-instance-profile`,
    {
      InstanceProfileName: instanceProfileName,
      Roles: [role.roleName],
    },
  );

  await Promise.all(
    Object.entries(props.environment).map(([key, value]) => {
      const name = `${trimTrailingSlash(props.parameterPath)}/${key}`;

      if (isSecret(value)) {
        return SSMParameter(`${id}-env-${key.toLowerCase()}`, {
          name,
          description: `Runtime configuration for ${props.appName}: ${key}`,
          type: "SecureString",
          value,
          tags,
        });
      }

      return SSMParameter(`${id}-env-${key.toLowerCase()}`, {
        name,
        description: `Runtime configuration for ${props.appName}: ${key}`,
        value,
        tags,
      });
    }),
  );

  const vpc = await Vpc(`${id}-vpc`, {
    cidrBlock: vpcCidrBlock,
    enableDnsSupport: true,
    enableDnsHostnames: true,
    region,
    tags,
  });

  const internetGateway = await InternetGateway(`${id}-igw`, {
    region,
    tags,
  });

  await InternetGatewayAttachment(`${id}-igw-attachment`, {
    internetGateway,
    vpc,
    region,
  });

  const routeTable = await RouteTable(`${id}-public-rt`, {
    vpc,
    region,
    tags,
  });

  await Route(`${id}-default-route`, {
    routeTable,
    region,
    destinationCidrBlock: "0.0.0.0/0",
    target: {
      internetGateway,
    },
  });

  const subnet = await Subnet(`${id}-public-subnet`, {
    vpc,
    region,
    cidrBlock: subnetCidrBlock,
    availabilityZone,
    mapPublicIpOnLaunch: true,
    tags,
  });

  await RouteTableAssociation(`${id}-public-association`, {
    routeTable,
    subnet,
  });

  const securityGroup = await SecurityGroup(`${id}-sg`, {
    vpc,
    region,
    description: `Ingress rules for ${props.appName}`,
    tags,
  });

  await Promise.all(
    httpCidrBlocks.map((cidr, index) =>
      SecurityGroupRule(`${id}-http-${index}`, {
        securityGroup,
        type: "ingress",
        protocol: "tcp",
        fromPort: port,
        toPort: port,
        cidrBlocks: [cidr],
        description: `Allow HTTP traffic on port ${port}`,
      }),
    ),
  );

  if (props.keyName && sshCidrBlocks.length > 0) {
    await Promise.all(
      sshCidrBlocks.map((cidr, index) =>
        SecurityGroupRule(`${id}-ssh-${index}`, {
          securityGroup,
          type: "ingress",
          protocol: "tcp",
          fromPort: 22,
          toPort: 22,
          cidrBlocks: [cidr],
          description: "Allow SSH access",
        }),
      ),
    );
  }

  const instance = await AWS.EC2.Instance(id, {
    AvailabilityZone: availabilityZone,
    IamInstanceProfile: instanceProfileName,
    ImageId: imageId,
    InstanceType: instanceType,
    KeyName: props.keyName ?? undefined,
    MetadataOptions: {
      HttpEndpoint: "enabled",
      HttpTokens: "required",
    },
    PropagateTagsToVolumeOnCreation: true,
    SecurityGroupIds: [securityGroup.groupId],
    SubnetId: subnet.subnetId,
    Tags: toAwsTags(tags),
    UserData: Buffer.from(
      buildUserData({
        appName: props.appName,
        artifactBucket: props.artifactBucket,
        artifactKey: props.artifactKey,
        artifactVersion: props.artifactVersion,
        layout,
        parameterPath: props.parameterPath,
        port,
        region,
      }),
      "utf8",
    ).toString("base64"),
    BlockDeviceMappings: [
      {
        DeviceName: "/dev/xvda",
        Ebs: {
          DeleteOnTermination: true,
          VolumeSize: rootVolumeSize,
          VolumeType: "gp3",
        },
      },
    ],
  });

  const host = instance.PublicDnsName || instance.PublicIp;
  const url = `http://${host}${port === 80 ? "" : `:${port}`}`;

  return {
    ...props,
    availabilityZone,
    imageId,
    instanceType,
    port,
    rootVolumeSize,
    publicIp: instance.PublicIp,
    instanceId: instance.InstanceId,
    publicDnsName: instance.PublicDnsName,
    url,
    vpcId: vpc.vpcId,
    subnetId: subnet.subnetId,
    securityGroupId: securityGroup.groupId,
    roleArn: role.arn,
    instanceProfileArn: instanceProfile.Arn,
  };
}

export function buildUserData({
  appName,
  artifactBucket,
  artifactKey,
  artifactVersion,
  layout = deriveRuntimeLayout(appName),
  parameterPath,
  port,
  region,
}: {
  appName: string;
  artifactBucket: string;
  artifactKey: string;
  artifactVersion?: string;
  layout?: RuntimeLayout;
  parameterPath: string;
  port: number;
  region: string;
  rootVolumeSize?: number | null;
}) {
  return `#!/bin/bash
set -euxo pipefail

export HOME=/root
export PATH=/usr/local/bin:/usr/bin:/bin

dnf update -y
dnf install -y jq unzip nodejs

curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL=/root/.bun
export PATH=$BUN_INSTALL/bin:$PATH

cat >/usr/local/bin/${layout.slug}-bootstrap <<'EOF'
#!/bin/bash
set -euo pipefail

export HOME=/root
export PATH=/root/.bun/bin:/usr/local/bin:/usr/bin:/bin
export AWS_REGION=${shellString(region)}

ARTIFACT_BUCKET=${shellString(artifactBucket)}
ARTIFACT_KEY=${shellString(artifactKey)}
ARTIFACT_VERSION=${shellString(artifactVersion ?? "unknown")}
PARAMETER_PATH=${shellString(trimTrailingSlash(parameterPath))}
APP_ROOT=${shellString(layout.appRoot)}
RELEASE_ROOT=${shellString(layout.releaseRoot)}
ENV_FILE=${shellString(layout.envFile)}
ARCHIVE_PATH=${shellString(layout.archivePath)}

rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT"

aws s3 cp "s3://$ARTIFACT_BUCKET/$ARTIFACT_KEY" "$ARCHIVE_PATH" --region "$AWS_REGION"
tar -xzf "$ARCHIVE_PATH" -C "$RELEASE_ROOT"

cat >"$ENV_FILE" <<ENVEOF
NODE_ENV=production
HOST=0.0.0.0
PORT=${port}
ARTIFACT_BUCKET=$ARTIFACT_BUCKET
ARTIFACT_KEY=$ARTIFACT_KEY
ARTIFACT_VERSION=$ARTIFACT_VERSION
ENVEOF

aws ssm get-parameters-by-path \\
  --path "$PARAMETER_PATH" \\
  --recursive \\
  --with-decryption \\
  --output json \\
  --region "$AWS_REGION" \\
| jq -r '.Parameters[] | "\\(.Name | split("/")[-1])=\\(.Value)"' >>"$ENV_FILE"
EOF

chmod +x /usr/local/bin/${layout.slug}-bootstrap
/usr/local/bin/${layout.slug}-bootstrap

cat >/etc/systemd/system/${layout.serviceName} <<'EOF'
[Unit]
Description=stackpanel ${appName}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${layout.releaseRoot}
Environment=PATH=/root/.bun/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=${layout.envFile}
ExecStart=/usr/bin/node ${layout.releaseRoot}/.output/server/index.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${layout.serviceName}
`;
}

async function resolveImageId(imageId: string, region: string) {
  if (imageId.startsWith("ami-")) {
    return imageId;
  }

  const match = imageId.match(/^\{\{resolve:ssm:([^}:]+)(?::\d+)?\}\}$/);
  if (!match) {
    return imageId;
  }

  const parameterName = match[1];
  const client = new SSMClient({ region });
  const response = await client.send(
    new GetParameterCommand({
      Name: parameterName,
    }),
  );
  const resolvedImageId = response.Parameter?.Value;

  if (!resolvedImageId?.startsWith("ami-")) {
    throw new Error(
      `Resolved AMI from SSM parameter ${parameterName} was not a valid EC2 image id.`,
    );
  }

  return resolvedImageId;
}

function toAwsTags(tags: Record<string, string>) {
  return Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));
}

function trimTrailingSlash(value: string) {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}

function shellString(value: string) {
  return JSON.stringify(value);
}

function sanitizeName(value: string) {
  const sanitized = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

  return sanitized || "app";
}
