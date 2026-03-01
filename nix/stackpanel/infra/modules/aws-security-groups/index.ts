// ==============================================================================
// AWS Security Groups Module
// ==============================================================================
import Infra from "@stackpanel/infra";
import { SecurityGroup } from "@stackpanel/infra/resources/security-group";

interface SecurityGroupRule {
  fromPort: number;
  toPort: number;
  protocol?: string;
  cidrBlocks?: string[];
  ipv6CidrBlocks?: string[];
  securityGroupIds?: string[];
  description?: string | null;
}

interface SecurityGroupInput {
  name: string;
  description?: string | null;
  ingress?: SecurityGroupRule[];
  egress?: SecurityGroupRule[];
  tags?: Record<string, string>;
}

interface AwsSecurityGroupsInputs {
  vpcId: string;
  groups: SecurityGroupInput[];
}

const infra = new Infra("aws-security-groups");
const inputs = infra.inputs<AwsSecurityGroupsInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const results: Record<string, string> = {};

for (const group of inputs.groups ?? []) {
  const securityGroup = await SecurityGroup(infra.id(group.name), {
    name: group.name,
    description: group.description ?? group.name,
    vpcId: inputs.vpcId,
    ingress: (group.ingress ?? []).map((rule) => ({
      fromPort: rule.fromPort,
      toPort: rule.toPort,
      protocol: rule.protocol ?? "tcp",
      cidrBlocks: rule.cidrBlocks ?? [],
      ipv6CidrBlocks: rule.ipv6CidrBlocks ?? [],
      securityGroupIds: rule.securityGroupIds ?? [],
      description: rule.description ?? undefined,
    })),
    egress: (group.egress ?? []).map((rule) => ({
      fromPort: rule.fromPort,
      toPort: rule.toPort,
      protocol: rule.protocol ?? "-1",
      cidrBlocks: rule.cidrBlocks ?? ["0.0.0.0/0"],
      ipv6CidrBlocks: rule.ipv6CidrBlocks ?? ["::/0"],
      securityGroupIds: rule.securityGroupIds ?? [],
      description: rule.description ?? undefined,
    })),
    tags: group.tags,
  });

  results[group.name] = securityGroup.groupId;
}

export default {
  groupIds: JSON.stringify(results),
};
