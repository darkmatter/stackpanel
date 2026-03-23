// ==============================================================================
// AWS IAM Role + Instance Profile Module
// ==============================================================================
import Infra from "@stackpanel/infra";
import { IamInstanceProfile } from "@stackpanel/infra/resources/iam-instance-profile";
import { IamRole } from "@stackpanel/infra/resources/iam-role";

interface InlinePolicy {
  name: string;
  document: Record<string, unknown>;
}

interface AwsIamInputs {
  role: {
    name: string;
    assumeRolePolicy?: Record<string, unknown> | null;
    managedPolicyArns?: string[];
    inlinePolicies?: InlinePolicy[];
    tags?: Record<string, string>;
  };
  instanceProfile?: {
    name?: string | null;
    tags?: Record<string, string>;
  };
}

const infra = new Infra("aws-iam");
const inputs = infra.inputs<AwsIamInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const assumeRolePolicy =
  inputs.role.assumeRolePolicy ?? {
    Version: "2012-10-17",
    Statement: [
      {
        Effect: "Allow",
        Principal: { Service: "ec2.amazonaws.com" },
        Action: "sts:AssumeRole",
      },
    ],
  };

const role = await IamRole(infra.id("role"), {
  roleName: inputs.role.name,
  assumeRolePolicy,
  description: `EC2 role for ${inputs.role.name}`,
  tags: inputs.role.tags,
  managedPolicyArns: inputs.role.managedPolicyArns,
  policies: (inputs.role.inlinePolicies ?? []).map((policy) => ({
    policyName: policy.name,
    policyDocument: policy.document,
  })),
});

const profileName =
  inputs.instanceProfile?.name ?? `${inputs.role.name}-profile`;

const instanceProfile = await IamInstanceProfile(infra.id("instance-profile"), {
  name: profileName,
  roleName: role.roleName,
  tags: inputs.instanceProfile?.tags,
});

export default {
  roleArn: role.arn,
  roleName: role.roleName,
  instanceProfileArn: instanceProfile.arn,
  instanceProfileName: instanceProfile.name,
};
