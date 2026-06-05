/// <reference path="../../sst/.sst/platform/config.d.ts" />

/**
 * SST Configuration for Authentik on Fly.io
 *
 * This configures:
 * 1. AWS OIDC provider for Fly.io
 * 2. IAM role for Authentik to access SSM
 * 3. State stored in Cloudflare R2
 */

export default $config({
  app(input) {
    return {
      name: "authentik-flyio",
      removal: input?.stage === "production" ? "retain" : "remove",
      protect: ["production"].includes(input?.stage ?? ""),
      home: "aws",
      providers: {
        aws: {
          region: "us-west-2",
        },
        cloudflare: true,
      },
    };
  },

  async run() {
    // Configuration
    const flyOrgId = "darkmatter";
    const flyAppName = "authentik-darkmatter";

    if (!flyOrgId) {
      throw new Error("FLY_ORG_ID environment variable is required. Get it from: fly orgs list");
    }

    // ========================================================================
    // AWS OIDC Provider for Fly.io (use existing)
    // ========================================================================

    // Use existing OIDC provider created by Terraform
    const flyOidcProviderArn = `arn:aws:iam::950224716579:oidc-provider/oidc.fly.io/${flyOrgId}`;
    const flyOidcProviderUrl = `oidc.fly.io/${flyOrgId}`;

    // ========================================================================
    // IAM Role for Authentik
    // ========================================================================

    const authentikRole = new aws.iam.Role("authentik-flyio", {
      name: "authentik-flyio-role",
      assumeRolePolicy: aws.iam.getPolicyDocumentOutput({
        statements: [{
          effect: "Allow",
          principals: [{
            type: "Federated",
            identifiers: [flyOidcProviderArn],
          }],
          actions: ["sts:AssumeRoleWithWebIdentity"],
          conditions: [
            {
              test: "StringEquals",
              variable: `${flyOidcProviderUrl}:aud`,
              values: ["sts.amazonaws.com"],
            },
            {
              test: "StringLike",
              variable: `${flyOidcProviderUrl}:sub`,
              values: [`${flyOrgId}:${flyAppName}:*`],
            },
          ],
        }],
      }).json,
      tags: {
        Name: "authentik-flyio-role",
        Environment: $app.stage,
        ManagedBy: "sst",
      },
    });

    // ========================================================================
    // Cloudflare R2 Bucket for Media Storage
    // ========================================================================

    const mediaBucket = new cloudflare.R2Bucket("authentik-media", {
      accountId: "acb126dc2c4cf93764fa69d9bd55a3cf",
      name: "authentik-media",
      location: "wnam", // Western North America
    });

    // Note: Cloudflare Worker for R2 access would need to be configured separately
    // using sst.cloudflare.Worker or by deploying the worker script directly
    // For now, R2 bucket is available for direct S3-compatible access from Authentik

    // ========================================================================
    // IAM Policy for SSM Access and R2
    // ========================================================================

    const ssmPolicy = new aws.iam.RolePolicy("authentik-ssm-read", {
      name: "authentik-ssm-read",
      role: authentikRole.id,
      policy: aws.iam.getPolicyDocumentOutput({
        statements: [
          {
            effect: "Allow",
            actions: [
              "ssm:GetParameter",
              "ssm:GetParameters",
              "ssm:GetParametersByPath",
            ],
            resources: [
              `arn:aws:ssm:*:*:parameter/authentik/*`,
            ],
          },
          {
            effect: "Allow",
            actions: ["ssm:DescribeParameters"],
            resources: ["*"],
          },
          // Allow using the KMS key by alias
          {
            effect: "Allow",
            actions: [
              "kms:Decrypt",
              "kms:GenerateDataKey*",
              "kms:DescribeKey"
            ],
            resources: ["*"],
            conditions: [
              {
                test: "StringLike",
                variable: "kms:RequestAlias",
                values: ["alias/parameter_store_key"],
              }
            ]
          },
          // allow  by id
          {
            effect: "Allow",
            actions: [
              "kms:Decrypt",
              "kms:GenerateDataKey*",
              "kms:DescribeKey"
            ],
            resources: [
              "arn:aws:kms:*:950224716579:key/136e1c0c-a9ac-42ee-96d5-2a00f9d816ea"
            ],
          },
          // Allow S3-compatible access to R2 bucket
          {
            effect: "Allow",
            actions: [
              "s3:ListBucket",
              "s3:GetObject",
              "s3:PutObject",
              "s3:DeleteObject",
            ],
            resources: [
              $interpolate`arn:aws:s3:::${mediaBucket.name}`,
              $interpolate`arn:aws:s3:::${mediaBucket.name}/*`,
            ],
          },
        ],
      }).json,
    });

    // ========================================================================
    // Store Outputs in SSM via Chamber
    // ========================================================================

    // Write role ARN to SSM for easy retrieval
    new aws.ssm.Parameter("authentik-role-arn", {
      name: "/authentik/aws_role_arn",
      type: "String",
      value: authentikRole.arn,
      description: "IAM Role ARN for Authentik to assume via OIDC",
      tags: {
        ManagedBy: "sst",
        Environment: $app.stage,
      },
    });

    // Write OIDC provider ARN
    new aws.ssm.Parameter("authentik-oidc-provider", {
      name: "/authentik/oidc_provider_arn",
      type: "String",
      value: flyOidcProviderArn,
      description: "OIDC Provider ARN for Fly.io",
      tags: {
        ManagedBy: "sst",
        Environment: $app.stage,
      },
    });

    // ========================================================================
    // Outputs
    // ========================================================================

    return {
      oidcProviderArn: flyOidcProviderArn,
      roleArn: authentikRole.arn,
      roleName: authentikRole.name,
      flyOrgId,
      flyAppName,
      r2BucketName: mediaBucket.name,
      r2BucketId: mediaBucket.id,
      setupInstructions: $interpolate`
╔════════════════════════════════════════════════════════════════════╗
║ Authentik Fly.io - AWS OIDC Setup Complete                        ║
╚════════════════════════════════════════════════════════════════════╝

Role ARN saved to SSM: /authentik/aws_role_arn

1. Set AWS_ROLE_ARN in Fly.io:
   fly secrets set AWS_ROLE_ARN="$(chamber read authentik aws_role_arn -q)" --app ${flyAppName}

2. Store application secrets in SSM via Chamber:
   chamber write authentik secret_key "$(openssl rand -base64 60)"
   chamber write authentik postgresql_password "YOUR_NEON_PASSWORD"
   chamber write authentik email_password "YOUR_MAILGUN_PASSWORD"

3. Deploy Authentik to Fly.io:
   cd apps/authentik-fly
   fly deploy --config fly.toml

Role ARN: ${authentikRole.arn}
`,
    };
  },
});
