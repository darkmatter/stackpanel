// ==============================================================================
// AWS Network Discovery Module
//
// Resolves default VPC + subnet IDs and emits them as JSON outputs.
// ==============================================================================
import Infra from "@stackpanel/infra";

interface AwsNetworkInputs {
  region?: string | null;
  vpc?: {
    id?: string | null;
    useDefault?: boolean;
  };
  subnets?: {
    ids?: string[];
    useDefault?: boolean;
  };
}

const infra = new Infra("aws-network");
const inputs = infra.inputs<AwsNetworkInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const { EC2Client, DescribeVpcsCommand, DescribeSubnetsCommand } =
  await import("@aws-sdk/client-ec2");

const region = inputs.region ?? process.env.AWS_REGION ?? process.env.AWS_DEFAULT_REGION;
const client = new EC2Client(region ? { region } : {});

let vpcId = inputs.vpc?.id ?? null;

if (!vpcId && inputs.vpc?.useDefault !== false) {
  const vpcs = await client.send(
    new DescribeVpcsCommand({
      Filters: [{ Name: "isDefault", Values: ["true"] }],
    }),
  );
  vpcId = vpcs.Vpcs?.[0]?.VpcId ?? null;
}

if (!vpcId) {
  throw new Error("aws-network: unable to resolve VPC ID");
}

let subnetIds = inputs.subnets?.ids ?? [];
let subnetAzs: string[] = [];

if (subnetIds.length === 0 && inputs.subnets?.useDefault !== false) {
  const subnets = await client.send(
    new DescribeSubnetsCommand({
      Filters: [{ Name: "vpc-id", Values: [vpcId] }],
    }),
  );
  subnetIds = (subnets.Subnets ?? []).map((subnet) => subnet.SubnetId!).filter(Boolean);
  subnetAzs = (subnets.Subnets ?? [])
    .map((subnet) => subnet.AvailabilityZone)
    .filter((az): az is string => Boolean(az));
}

export default {
  vpcId,
  subnetIds: JSON.stringify(subnetIds),
  subnetAzs: JSON.stringify(subnetAzs),
};
