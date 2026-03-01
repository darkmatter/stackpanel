import { AccountId } from "alchemy/aws";
import { GitHubOIDCProvider } from "alchemy/aws/oidc";
import Infra from "@stackpanel/infra";
import { IamRole } from "@stackpanel/infra/resources/iam-role";
import { KmsAlias } from "@stackpanel/infra/resources/kms-alias";
import { KmsKey } from "@stackpanel/infra/resources/kms-key";
import {
  buildAssumeRolePolicy,
  buildKmsKeyPolicy,
  buildRoleKmsInlinePolicy,
  githubActionsProviderArn,
} from "./policies";

const infra = new Infra("aws-secrets");
const inputs = infra.inputs(process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES);

const accountId = await AccountId();
const assumeRolePolicy = buildAssumeRolePolicy(inputs.oidc, accountId) as any;

const roleTags = {
  Project: inputs.projectName,
  ManagedBy: "stackpanel-infra",
};

const rolePolicyName = `${inputs.iam.roleName}-kms-policy`;

const role = await IamRole(infra.id("role"), {
  roleName: inputs.iam.roleName,
  assumeRolePolicy,
  description: `IAM role for ${inputs.projectName} secrets access`,
  tags: roleTags,
  managedPolicyArns: inputs.iam.additionalPolicies ?? [],
});

let resolvedOidcProviderArn = githubActionsProviderArn(accountId);

if (inputs.oidc.provider === "github-actions") {
  const oidcProvider = await GitHubOIDCProvider(infra.id("oidc"), {
    adopt: true,
    owner: inputs.oidc.githubActions.org,
    repository: inputs.oidc.githubActions.repo,
    roleArn: role.arn,
  } as any);
  resolvedOidcProviderArn = oidcProvider.providerArn;
}

const kmsKey = await KmsKey(infra.id("kms-key"), {
  aliasName: `alias/${inputs.kms.alias}`,
  description: `KMS key for encrypting ${inputs.projectName} secrets`,
  enableKeyRotation: true,
  deletionWindowInDays: inputs.kms.deletionWindowDays,
  policy: buildKmsKeyPolicy(accountId, role.arn),
  tags: {
    Name: inputs.kms.alias,
    ...roleTags,
  },
});

const kmsAlias = await KmsAlias(infra.id("kms-alias"), {
  aliasName: `alias/${inputs.kms.alias}`,
  targetKeyId: kmsKey.keyId,
});

await IamRole(infra.id("role"), {
  roleName: inputs.iam.roleName,
  assumeRolePolicy,
  description: `IAM role for ${inputs.projectName} secrets access`,
  tags: roleTags,
  managedPolicyArns: inputs.iam.additionalPolicies ?? [],
  policies: [
    {
      policyName: rolePolicyName,
      ...buildRoleKmsInlinePolicy(inputs.kms.alias, kmsKey.arn),
    },
  ],
});

export default {
  roleArn: role.arn,
  roleName: role.roleName,
  kmsKeyArn: kmsKey.arn,
  kmsKeyId: kmsKey.keyId,
  kmsAliasName: kmsAlias.aliasName,
  oidcProviderArn: resolvedOidcProviderArn,
};
