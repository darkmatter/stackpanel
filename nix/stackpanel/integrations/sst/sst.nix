# ==============================================================================
# sst.nix - SST Extension
#
# A builtin stackpanel extension for AWS infrastructure provisioning.
#
# This extension uses core stackpanel features:
#   - File generation: Creates sst.config.ts with OIDC/KMS setup
#   - Scripts: sst:deploy, sst:dev, sst:remove, sst:outputs commands
#   - Packages: awscli2, jq
#   - Module requirements: Declares required secrets (CLOUDFLARE_API_TOKEN)
#
# AWS Infrastructure provisioned:
#   - KMS key for encrypting/decrypting secrets
#   - IAM role with OIDC authentication
#   - Multiple OIDC provider support (GitHub Actions, Fly.io, Roles Anywhere)
#
# Usage:
#   stackpanel.sst.enable = true;  # Enabled by default
#   stackpanel.sst.oidc.provider = "github-actions";
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.sst;

  # ==========================================================================
  # Inherited defaults from core config (convention-based prefilling)
  # ==========================================================================

  # Project name from core config
  projectName = config.stackpanel.name or "my-project";

  # AWS config (if roles-anywhere is configured, inherit region/account-id)
  awsCfg = config.stackpanel.aws.roles-anywhere or { };
  defaultRegion = awsCfg.region or "us-west-2";
  defaultAccountId = awsCfg.account-id or "";

  # GitHub org/repo from project config
  projectCfg = config.stackpanel.project;
  defaultGithubOrg = projectCfg.owner;
  defaultGithubRepo = if projectCfg.repo != "" then projectCfg.repo else "*";

  # OIDC provider configurations
  oidcProviders = {
    github-actions = {
      name = "GitHub Actions";
      providerUrl = "token.actions.githubusercontent.com";
      audienceValue = "sts.amazonaws.com";
    };
    flyio = {
      name = "Fly.io";
      providerUrl = "oidc.fly.io";
      audienceValue = "sts.amazonaws.com";
    };
    roles-anywhere = {
      name = "AWS Roles Anywhere";
      # Uses X.509 certificates instead of OIDC tokens
      providerUrl = null;
      audienceValue = null;
    };
  };

  # Generate the SST config file content
  generateSstConfig =
    let
      # =========================================================================
      # All interpolated values extracted at the top (convention)
      # =========================================================================
      provider = cfg.oidc.provider;
      providerConfig = oidcProviders.${provider} or null;
      providerName = providerConfig.name or provider;

      # Core config
      sstProjectName = cfg.project-name;
      region = cfg.region;
      accountId = cfg.account-id;

      # IAM config
      roleName = cfg.iam.role-name;

      # KMS config
      kmsEnabled = cfg.kms.enable;
      kmsAlias = cfg.kms.alias;
      kmsDeletionDays = toString cfg.kms.deletion-window-days;

      # GitHub Actions OIDC config
      githubOrg = cfg.oidc.github-actions.org;
      githubRepo = cfg.oidc.github-actions.repo;

      # Fly.io OIDC config
      flyOrgId = cfg.oidc.flyio.org-id;
      flyAppName = cfg.oidc.flyio.app-name;

      # Roles Anywhere config
      trustAnchorArn = cfg.oidc.roles-anywhere.trust-anchor-arn;

      # =========================================================================
      # Provider-specific OIDC setup
      # =========================================================================
      oidcSetup =
        if provider == "github-actions" then
          ''
            // syntax: ts
            // ========================================================================
            // GitHub Actions OIDC Provider
            // ========================================================================
            const githubOrg = "${githubOrg}";
            const githubRepo = "${githubRepo}";

            // Check if GitHub OIDC provider already exists (it's a singleton per account)
            const existingOidcArn = `arn:aws:iam::${accountId}:oidc-provider/token.actions.githubusercontent.com`;

            // Use aws.iam.OpenIdConnectProvider.get to adopt existing provider
            // This avoids the "EntityAlreadyExists" error when the provider was created outside SST
            const githubOidcProvider = aws.iam.OpenIdConnectProvider.get("github-oidc", existingOidcArn);

            const oidcProviderArn = githubOidcProvider.arn;
            const oidcProviderUrl = "token.actions.githubusercontent.com";
            const oidcConditions = [
              {
                test: "StringEquals",
                variable: `''${oidcProviderUrl}:aud`,
                values: ["sts.amazonaws.com"],
              },
              {
                test: "StringLike",
                variable: `''${oidcProviderUrl}:sub`,
                values: [`repo:''${githubOrg}/''${githubRepo}:*`],
              },
            ];
          ''
        else if provider == "flyio" then
          ''
            // syntax: ts
            // ========================================================================
            // Fly.io OIDC Provider
            // ========================================================================
            const flyOrgId = "${flyOrgId}";
            const flyAppName = "${flyAppName}";

            const flyOidcProvider = new aws.iam.OpenIdConnectProvider("flyio-oidc", {
              url: `https://oidc.fly.io/''${flyOrgId}`,
              clientIdLists: ["sts.amazonaws.com"],
              thumbprintLists: ["6938fd4d98bab03faadb97b34396831e3780aea1"],
              tags: {
                Name: "flyio-oidc",
                ManagedBy: "sst",
              },
            });

            const oidcProviderArn = flyOidcProvider.arn;
            const oidcProviderUrl = `oidc.fly.io/''${flyOrgId}`;
            const oidcConditions = [
              {
                test: "StringEquals",
                variable: `''${oidcProviderUrl}:aud`,
                values: ["sts.amazonaws.com"],
              },
              {
                test: "StringLike",
                variable: `''${oidcProviderUrl}:sub`,
                values: [`''${flyOrgId}:''${flyAppName}:*`],
              },
            ];
          ''
        else if provider == "roles-anywhere" then
          ''
            // syntax: ts
            // ========================================================================
            // AWS Roles Anywhere (X.509 Certificate Auth)
            // ========================================================================
            const trustAnchorArn = "${trustAnchorArn}";

            // Note: Roles Anywhere uses X.509 certificates, not OIDC.
            // The trust anchor must be created separately or referenced by ARN.
            const oidcProviderArn = null;
            const oidcProviderUrl = null;
            const oidcConditions = [];
          ''
        else
          ''
            // No OIDC provider configured
            const oidcProviderArn = null;
            const oidcProviderUrl = null;
            const oidcConditions = [];
          '';

      # =========================================================================
      # IAM role creation (differs for Roles Anywhere vs OIDC)
      # =========================================================================
      iamRoleSetup =
        if provider == "roles-anywhere" then
          ''
            // syntax: ts
            // ========================================================================
            // IAM Role for Roles Anywhere
            // ========================================================================
            const roleName = "${roleName}";

            const secretsRole = new aws.iam.Role(roleName, {
              name: roleName,
              assumeRolePolicy: aws.iam.getPolicyDocumentOutput({
                statements: [{
                  effect: "Allow",
                  principals: [{
                    type: "Service",
                    identifiers: ["rolesanywhere.amazonaws.com"],
                  }],
                  actions: [
                    "sts:AssumeRole",
                    "sts:TagSession",
                    "sts:SetSourceIdentity",
                  ],
                  conditions: [
                    {
                      test: "ArnEquals",
                      variable: "aws:SourceArn",
                      values: [trustAnchorArn],
                    },
                  ],
                }],
              }).json,
              tags: {
                Name: roleName,
                Environment: $app.stage,
                ManagedBy: "sst",
              },
            });
          ''
        else
          ''
            // syntax: ts
            // ========================================================================
            // IAM Role for OIDC Authentication
            // ========================================================================
            const roleName = "${roleName}";

            const secretsRole = new aws.iam.Role(roleName, {
              name: roleName,
              assumeRolePolicy: aws.iam.getPolicyDocumentOutput({
                statements: [{
                  effect: "Allow",
                  principals: [{
                    type: "Federated",
                    identifiers: [oidcProviderArn],
                  }],
                  actions: ["sts:AssumeRoleWithWebIdentity"],
                  conditions: oidcConditions,
                }],
              }).json,
              tags: {
                Name: roleName,
                Environment: $app.stage,
                ManagedBy: "sst",
              },
            });
          '';

      # =========================================================================
      # KMS key setup
      # =========================================================================
      kmsSetup = lib.optionalString kmsEnabled ''
        // syntax: ts
        // ========================================================================
        // KMS Key for Secrets Encryption
        // ========================================================================
        const kmsAlias = "${kmsAlias}";
        const kmsDeletionDays = ${kmsDeletionDays};
        const awsAccountId = "${accountId}";

        const secretsKey = new aws.kms.Key(kmsAlias, {
          description: "KMS key for encrypting stackpanel secrets",
          enableKeyRotation: true,
          deletionWindowInDays: kmsDeletionDays,
          policy: aws.iam.getPolicyDocumentOutput({
            statements: [
              // Allow root account full access
              {
                effect: "Allow",
                principals: [{
                  type: "AWS",
                  identifiers: [`arn:aws:iam::''${awsAccountId}:root`],
                }],
                actions: ["kms:*"],
                resources: ["*"],
              },
              // Allow the secrets role to use the key
              {
                effect: "Allow",
                principals: [{
                  type: "AWS",
                  identifiers: [secretsRole.arn],
                }],
                actions: [
                  "kms:Decrypt",
                  "kms:Encrypt",
                  "kms:GenerateDataKey*",
                  "kms:DescribeKey",
                ],
                resources: ["*"],
              },
            ],
          }).json,
          tags: {
            Name: kmsAlias,
            Environment: $app.stage,
            ManagedBy: "sst",
          },
        });

        const secretsKeyAlias = new aws.kms.Alias(`''${kmsAlias}-alias`, {
          name: `alias/''${kmsAlias}`,
          targetKeyId: secretsKey.id,
        });
      '';

      # =========================================================================
      # IAM policy for KMS access
      # =========================================================================
      kmsPolicySetup = lib.optionalString kmsEnabled ''
        // syntax: ts
        // ========================================================================
        // IAM Policy for KMS Access
        // ========================================================================
        new aws.iam.RolePolicy(`''${roleName}-kms`, {
          name: `''${roleName}-kms-policy`,
          role: secretsRole.id,
          policy: aws.iam.getPolicyDocumentOutput({
            statements: [
              {
                effect: "Allow",
                actions: [
                  "kms:Decrypt",
                  "kms:Encrypt",
                  "kms:GenerateDataKey*",
                  "kms:DescribeKey",
                ],
                resources: [secretsKey.arn],
              },
              {
                effect: "Allow",
                actions: ["kms:Decrypt"],
                resources: ["*"],
                conditions: [
                  {
                    test: "StringLike",
                    variable: "kms:RequestAlias",
                    values: [`alias/''${kmsAlias}`],
                  },
                ],
              },
            ],
          }).json,
        });
      '';

      # =========================================================================
      # Outputs
      # =========================================================================
      kmsOutputs = lib.optionalString kmsEnabled ''
        kmsKeyArn: secretsKey.arn,
        kmsKeyId: secretsKey.id,
        kmsKeyAlias: secretsKeyAlias.name,
      '';
      githubOutputs = lib.optionalString (provider == "github-actions") ''
        oidcProviderArn: githubOidcProvider.arn,
      '';
      flyioOutputs = lib.optionalString (provider == "flyio") ''
        oidcProviderArn: flyOidcProvider.arn,
        flyOrgId,
        flyAppName,
      '';
      kmsInstructions = lib.optionalString kmsEnabled "KMS Key Alias: alias/\${kmsAlias}";

      outputs = ''
            // ========================================================================
            // Outputs
            // ========================================================================
            const providerType = "${provider}";
            const providerDisplayName = "${providerName}";

            return {
              roleArn: secretsRole.arn,
              roleName: secretsRole.name,
              ${kmsOutputs}${githubOutputs}${flyioOutputs}provider: providerType,
              setupInstructions: $interpolate`
        ╔════════════════════════════════════════════════════════════════════╗
        ║ Stackpanel Infrastructure Setup Complete                           ║
        ╚════════════════════════════════════════════════════════════════════╝

        Role ARN: ''${secretsRole.arn}
        ${kmsInstructions}

        Provider: ''${providerDisplayName}

        To use this infrastructure:
        1. Configure your secrets with the KMS key
        2. Use the IAM role for decryption in your applications
        `,
            };
      '';

      # =========================================================================
      # Header comment
      # =========================================================================
      kmsComment = lib.optionalString kmsEnabled "3. KMS key for secrets encryption/decryption";
    in
    ''
      /// <reference path="./.sst/platform/config.d.ts" />

      /**
       * SST Configuration for Stackpanel Infrastructure
       *
       * This configures:
       * 1. OIDC provider for ${providerName}
       * 2. IAM role for secrets access
       * ${kmsComment}
       *
       * Generated by stackpanel - do not edit manually.
       * Regenerate with: nix run .#generate
       */

      // ===========================================================================
      // Interpolated values from Nix configuration
      // ===========================================================================
      const projectName = "${sstProjectName}";
      const awsRegion = "${region}";

      export default $config({
        app(input) {
          return {
            name: projectName,
            removal: input?.stage === "production" ? "retain" : "remove",
            protect: ["production"].includes(input?.stage ?? ""),
            home: "aws",
            providers: {
              aws: {
                region: awsRegion,
              },
            },
          };
        },

        async run() {
      ${oidcSetup}
      ${iamRoleSetup}
      ${kmsSetup}
      ${kmsPolicySetup}
      ${outputs}
        },
      });
    '';

  # ==========================================================================
  # Package.json generation
  # ==========================================================================
  packageDir = builtins.dirOf cfg.config-path;

  defaultPackageScripts = {
    "sst:deploy" = "bunx sst deploy";
    "sst:dev" = "bunx sst dev";
    "sst:remove" = "bunx sst remove";
  };

  defaultPackageDeps = {
    sst = "^3.17.25";
    "@pulumi/aws" = "^7.15.0";
  };

  packageJsonValue = {
    name = cfg.package.name;
    type = "module";
    private = true;
    scripts = defaultPackageScripts // cfg.package.scripts;
    dependencies = defaultPackageDeps // cfg.package.dependencies;
  };

  flattenJsonSetOps =
    prefix: value:
    if builtins.isAttrs value then
      lib.flatten (lib.mapAttrsToList (key: nested: flattenJsonSetOps (prefix ++ [ key ]) nested) value)
    else
      [
        {
          op = "set";
          path = prefix;
          inherit value;
        }
      ];
in
{
  options.stackpanel.sst = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SST infrastructure provisioning";
    };

    project-name = lib.mkOption {
      type = lib.types.str;
      default = projectName;
      description = "SST project name (used in resource naming)";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = defaultRegion;
      description = "AWS region for infrastructure (inherits from stackpanel.aws.roles-anywhere.region)";
    };

    account-id = lib.mkOption {
      type = lib.types.str;
      default = defaultAccountId;
      description = "AWS account ID (inherits from stackpanel.aws.roles-anywhere.account-id)";
    };

    config-path = lib.mkOption {
      type = lib.types.str;
      default = "packages/infra/sst.config.ts";
      description = "Path to generate the SST config file (relative to project root)";
    };

    # Package.json generation (enables turbo integration)
    package = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Generate a package.json in the SST directory, making it a workspace package for Turborepo";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "@${projectName}/infra";
        description = "NPM package name for the infrastructure package";
      };

      dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional dependencies to include in the generated package.json (beyond sst and @pulumi/aws)";
      };

      scripts = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional scripts to include in the generated package.json (deploy, dev, remove are included by default)";
      };
    };

    # KMS configuration
    kms = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create a KMS key for secrets encryption";
      };

      alias = lib.mkOption {
        type = lib.types.str;
        default = "${projectName}-secrets";
        description = "KMS key alias";
      };

      deletion-window-days = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Number of days before KMS key deletion";
      };
    };

    # OIDC configuration
    oidc = {
      provider = lib.mkOption {
        type = lib.types.enum [
          "github-actions"
          "flyio"
          "roles-anywhere"
          "none"
        ];
        default = "github-actions";
        description = "OIDC provider type for IAM role assumption";
      };

      github-actions = {
        org = lib.mkOption {
          type = lib.types.str;
          default = defaultGithubOrg;
          description = "GitHub organization name (inherits from stackpanel.project.owner)";
        };

        repo = lib.mkOption {
          type = lib.types.str;
          default = defaultGithubRepo;
          description = "GitHub repository name (inherits from stackpanel.project.repo, or * for all repos in org)";
        };

        branch = lib.mkOption {
          type = lib.types.str;
          default = "*";
          description = "Branch filter for OIDC subject";
        };
      };

      flyio = {
        org-id = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Fly.io organization ID";
        };

        app-name = lib.mkOption {
          type = lib.types.str;
          default = "*";
          description = "Fly.io app name (or * for all apps)";
        };
      };

      roles-anywhere = {
        trust-anchor-arn = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "ARN of the Roles Anywhere trust anchor";
        };
      };
    };

    # IAM configuration
    iam = {
      role-name = lib.mkOption {
        type = lib.types.str;
        default = "${projectName}-secrets-role";
        description = "Name of the IAM role to create";
      };

      additional-policies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional IAM policy ARNs to attach to the role";
      };
    };
  };

  config = lib.mkMerge [
    # =========================================================================
    # Force KMS on when variables backend is "chamber"
    # =========================================================================
    (lib.mkIf (config.stackpanel.secrets.backend == "chamber") {
      stackpanel.sst.kms.enable = lib.mkForce true;
    })

    (lib.mkIf cfg.enable {
      # =========================================================================
      # Extension Registration
      # =========================================================================
      # Register SST as a builtin extension so it appears in the extensions UI
      # and can be managed like any other extension.
      stackpanel.extensions.sst = {
        name = "SST Infrastructure";
        enabled = true;
        builtin = true;
        priority = 10; # Load early since other extensions may depend on AWS infra

        # Source directory for file-based scripts (reference implementation)
        # Scripts in src/scripts/ are used via path option below
        srcDir = ./src;

        tags = [
          "aws"
          "infrastructure"
          "secrets"
          "oidc"
        ];

        # Declare which core features this extension uses
        features = {
          files = true; # Generates sst.config.ts
          scripts = true; # sst:deploy, sst:dev, etc.
          secrets = true; # Manages AWS secrets infrastructure
          packages = true; # awscli2, jq
        };

        # Status panel showing SST configuration
        panels = [
          {
            id = "sst-status";
            title = "SST Infrastructure";
            description = "AWS infrastructure status and configuration";
            type = "PANEL_TYPE_STATUS";
            order = 1;
            fields = [
              {
                name = "metrics";
                type = "FIELD_TYPE_STRING";
                value = builtins.toJSON [
                  {
                    label = "OIDC Provider";
                    value = cfg.oidc.provider;
                    status = "ok";
                  }
                  {
                    label = "AWS Region";
                    value = cfg.region;
                    status = "ok";
                  }
                  {
                    label = "KMS Encryption";
                    value = if cfg.kms.enable then "Enabled" else "Disabled";
                    status = if cfg.kms.enable then "ok" else "warning";
                  }
                  {
                    label = "IAM Role";
                    value = cfg.iam.role-name;
                    status = "ok";
                  }
                  {
                    label = "Config Path";
                    value = cfg.config-path;
                    status = "ok";
                  }
                  {
                    label = "Package";
                    value = if cfg.package.enable then cfg.package.name else "Disabled";
                    status = if cfg.package.enable then "ok" else "warning";
                  }
                ];
              }
            ];
          }
        ];
      };

      # =========================================================================
      # Module Requirements
      # =========================================================================
      # Declare variable requirements for UI/agent to track
      stackpanel.moduleRequirements.sst = {
        requires = [
          {
            key = "CLOUDFLARE_API_TOKEN";
            description = "Cloudflare API token for SST state storage (Workers KV)";
            sensitive = true;
            action = {
              type = "add-secret";
              label = "Add Cloudflare Token";
              url = "https://dash.cloudflare.com/profile/api-tokens";
            };
          }
        ];
        provides = [
          "SST_STAGE"
        ];
      };

      # Generate the SST config file
      stackpanel.files.entries = {
        "${cfg.config-path}" = {
          text = generateSstConfig;
          mode = "0644";
        };
      }
      // lib.optionalAttrs cfg.package.enable {
        "${packageDir}/package.json" = {
          type = "json-ops";
          adopt = "backup";
          ops = flattenJsonSetOps [ ] packageJsonValue;
          mode = "0644";
          source = lib.mkDefault "sst";
          description = lib.mkDefault "SST infrastructure package";
        };
      };

      # Add SST CLI and related packages
      stackpanel.devshell.packages = [
        pkgs.awscli2
        pkgs.jq
      ];

      # Add scripts for SST
      # Using path option for file-based scripts (reference implementation)
      stackpanel.scripts = {
        "sst:deploy" = {
          description = "Deploy SST infrastructure";
          path = ./src/scripts/deploy.sh;
          env.SST_CONFIG_PATH = cfg.config-path;
        };

        "sst:dev" = {
          description = "Start SST dev mode";
          path = ./src/scripts/dev.sh;
          env.SST_CONFIG_PATH = cfg.config-path;
        };

        "sst:remove" = {
          description = "Remove SST infrastructure";
          path = ./src/scripts/remove.sh;
          env.SST_CONFIG_PATH = cfg.config-path;
        };

        "sst:outputs" = {
          description = "Show SST stack outputs";
          path = ./src/scripts/outputs.sh;
          env.SST_CONFIG_PATH = cfg.config-path;
        };
      };

      # Add MOTD entries
      stackpanel.motd.commands = [
        {
          name = "sst:deploy";
          description = "Deploy infrastructure";
        }
        {
          name = "sst:outputs";
          description = "Show stack outputs";
        }
      ];

      stackpanel.motd.features = [
        "SST Infrastructure (${cfg.oidc.provider})"
      ]
      ++ lib.optional cfg.kms.enable "KMS Encryption";

      # Serializable config for the agent
      stackpanel.serializable.sst = {
        inherit (cfg)
          enable
          project-name
          region
          account-id
          config-path
          ;
        package = {
          inherit (cfg.package) enable name;
          path = packageDir;
        };
        kms = {
          inherit (cfg.kms) enable alias;
        };
        oidc = {
          inherit (cfg.oidc) provider;
          github-actions = cfg.oidc.github-actions;
          flyio = cfg.oidc.flyio;
          roles-anywhere = {
            trust-anchor-arn = cfg.oidc.roles-anywhere.trust-anchor-arn;
          };
        };
        iam = {
          inherit (cfg.iam) role-name;
        };
      };
    })
  ];
}
