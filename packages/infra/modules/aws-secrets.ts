// ==============================================================================
// AWS Secrets Infrastructure Module
//
// Provisions:
//   - GitHub Actions / Fly.io OIDC provider
//   - IAM role with OIDC trust policy
//   - KMS key + alias for secrets encryption
//   - KMS access policy attached to the role
//
// This is a stackpanel infra module. It uses the @stackpanel/infra library
// for input resolution and output collection.
// ==============================================================================
import { Role } from "alchemy/aws";
import AWS from "alchemy/aws/control";
import { GitHubOIDCProvider } from "alchemy/aws/oidc";
import { AccountId } from "alchemy/aws";
import Infra from "@stackpanel/infra";

const infra = new Infra("aws-secrets");
const inputs = infra.inputs(process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES);

// ============================================================================
// IAM Role
// ============================================================================

const accountId = await AccountId();
const oidcProviderUrl = "token.actions.githubusercontent.com";
const oidcProviderArn = `arn:aws:iam::${accountId}:oidc-provider/${oidcProviderUrl}`;

// Build assume role policy based on OIDC provider type
let assumeRolePolicy: any;

switch (inputs.oidc.provider) {
	case "github-actions": {
		const { org, repo } = inputs.oidc.githubActions;
		assumeRolePolicy = {
			Version: "2012-10-17" as const,
			Statement: [
				{
					Effect: "Allow" as const,
					Principal: {
						Federated: oidcProviderArn,
					},
					Action: "sts:AssumeRoleWithWebIdentity",
					Condition: {
						StringEquals: {
							[`${oidcProviderUrl}:aud`]: "sts.amazonaws.com",
						},
						StringLike: {
							[`${oidcProviderUrl}:sub`]: `repo:${org}/${repo}:*`,
						},
					},
				},
			],
		};
		break;
	}

	case "flyio": {
		const { orgId, appName } = inputs.oidc.flyio;
		const flyOidcUrl = `oidc.fly.io/${orgId}`;
		assumeRolePolicy = {
			Version: "2012-10-17" as const,
			Statement: [
				{
					Effect: "Allow" as const,
					Principal: {
						Federated: `arn:aws:iam::${accountId}:oidc-provider/${flyOidcUrl}`,
					},
					Action: "sts:AssumeRoleWithWebIdentity",
					Condition: {
						StringEquals: {
							[`${flyOidcUrl}:aud`]: "sts.amazonaws.com",
						},
						StringLike: {
							[`${flyOidcUrl}:sub`]: `${orgId}:${appName}:*`,
						},
					},
				},
			],
		};
		break;
	}

	case "roles-anywhere": {
		assumeRolePolicy = {
			Version: "2012-10-17" as const,
			Statement: [
				{
					Effect: "Allow" as const,
					Principal: {
						Service: "rolesanywhere.amazonaws.com",
					},
					Action: [
						"sts:AssumeRole",
						"sts:TagSession",
						"sts:SetSourceIdentity",
					],
					Condition: {
						ArnEquals: {
							"aws:SourceArn":
								inputs.oidc.rolesAnywhere.trustAnchorArn,
						},
					},
				},
			],
		};
		break;
	}

	default: {
		// No OIDC — basic role with no trust policy
		assumeRolePolicy = {
			Version: "2012-10-17" as const,
			Statement: [],
		};
	}
}

const role = await Role(infra.id("role"), {
	roleName: inputs.iam.roleName,
	assumeRolePolicy,
	description: `IAM role for ${inputs.projectName} secrets access`,
	tags: {
		Project: inputs.projectName,
		ManagedBy: "stackpanel-infra",
	},
	managedPolicyArns: inputs.iam.additionalPolicies ?? [],
});

// ============================================================================
// GitHub OIDC Provider (only for github-actions provider)
// ============================================================================
let resolvedOidcProviderArn = oidcProviderArn;

if (inputs.oidc.provider === "github-actions") {
	const oidcProvider = await GitHubOIDCProvider(infra.id("oidc"), {
		owner: inputs.oidc.githubActions.org,
		repository: inputs.oidc.githubActions.repo,
		roleArn: role.arn,
	});
	resolvedOidcProviderArn = oidcProvider.providerArn;
}

// ============================================================================
// KMS Key + Alias
// ============================================================================

const kmsKeyPolicy = JSON.stringify({
	Version: "2012-10-17",
	Statement: [
		// Root account gets full access
		{
			Effect: "Allow",
			Principal: {
				AWS: `arn:aws:iam::${accountId}:root`,
			},
			Action: "kms:*",
			Resource: "*",
		},
		// The secrets role gets encrypt/decrypt
		{
			Effect: "Allow",
			Principal: {
				AWS: role.arn,
			},
			Action: [
				"kms:Decrypt",
				"kms:Encrypt",
				"kms:GenerateDataKey*",
				"kms:DescribeKey",
			],
			Resource: "*",
		},
	],
});

const kmsKey = await AWS.KMS.Key(infra.id("kms-key"), {
	Description: `KMS key for encrypting ${inputs.projectName} secrets`,
	EnableKeyRotation: true,
	PendingWindowInDays: inputs.kms.deletionWindowDays,
	KeyPolicy: JSON.parse(kmsKeyPolicy),
	Tags: Object.entries({
		Name: inputs.kms.alias,
		Project: inputs.projectName,
		ManagedBy: "stackpanel-infra",
	}).map(([Key, Value]) => ({ Key, Value })),
	adopt: true,
});

const kmsAlias = await AWS.KMS.Alias(infra.id("kms-alias"), {
	AliasName: `alias/${inputs.kms.alias}`,
	TargetKeyId: kmsKey.KeyId,
	adopt: true,
});

// Grant the role KMS permissions via inline policy
await Role(infra.id("role"), {
	roleName: inputs.iam.roleName,
	assumeRolePolicy,
	description: `IAM role for ${inputs.projectName} secrets access`,
	tags: {
		Project: inputs.projectName,
		ManagedBy: "stackpanel-infra",
	},
	managedPolicyArns: inputs.iam.additionalPolicies ?? [],
	policies: [
		{
			policyName: `${inputs.iam.roleName}-kms-policy`,
			policyDocument: {
				Version: "2012-10-17",
				Statement: [
					{
						Effect: "Allow",
						Action: [
							"kms:Decrypt",
							"kms:Encrypt",
							"kms:GenerateDataKey*",
							"kms:DescribeKey",
						],
						Resource: kmsKey.Arn,
					},
					{
						Effect: "Allow",
						Action: ["kms:Decrypt"],
						Resource: "*",
						Condition: {
							StringLike: {
								"kms:RequestAlias": `alias/${inputs.kms.alias}`,
							},
						},
					},
				],
			},
		},
	],
});

// ============================================================================
// Outputs
// ============================================================================
export default {
	roleArn: role.arn,
	roleName: role.roleName,
	kmsKeyArn: kmsKey.Arn,
	kmsKeyId: kmsKey.KeyId,
	kmsAliasName: kmsAlias.AliasName,
	oidcProviderArn: resolvedOidcProviderArn,
};
