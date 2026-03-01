# ==============================================================================
# infra/modules/aws-secrets/module.nix
#
# AWS Secrets Infrastructure infra module.
#
# Provisions:
#   - GitHub Actions / Fly.io / Roles Anywhere OIDC provider
#   - IAM role with OIDC trust policy
#   - KMS key + alias for secrets encryption
#   - SSM Parameter Store policies for secrets group key storage
#
# This is the direct replacement for the SST-based stackpanel.sst module.
#
# Usage:
#   stackpanel.infra.enable = true;
#   stackpanel.infra.aws.secrets = {
#     enable = true;
#     oidc.provider = "github-actions";
#     oidc.github-actions = { org = "my-org"; repo = "my-repo"; };
#   };
#
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.aws.secrets;

  # Inherited defaults from core config
  projectName = config.stackpanel.name or "my-project";

  # AWS config (inherit from roles-anywhere if available)
  awsCfg = config.stackpanel.aws.roles-anywhere or { };
  defaultRegion = awsCfg.region or "us-west-2";
  defaultAccountId = awsCfg.account-id or "";

  # GitHub org/repo from project config
  projectCfg = config.stackpanel.project;
  defaultGithubOrg = projectCfg.owner;
  defaultGithubRepo = if projectCfg.repo != "" then projectCfg.repo else "*";

  # Secrets groups config (for SSM key paths)
  secretsGroups = config.stackpanel.secrets.groups or { };
  chamberPrefix = config.stackpanel.secrets.chamber.service-prefix or projectName;

  # Collect all SSM paths from groups
  groupSsmPaths = lib.mapAttrsToList (_: g: g.ssm-path) secretsGroups;

  # Compute the SSM path prefix for wildcard IAM policy
  # All group keys live under /{prefix}/keys/*
  ssmKeyPrefix = "/${chamberPrefix}/keys";

in
{
  # ============================================================================
  # Options
  # ============================================================================
  options.stackpanel.infra.aws.secrets = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable AWS secrets infrastructure (OIDC + IAM + KMS).
        Enabled by default — set to false to explicitly disable.
      '';
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = defaultRegion;
      description = "AWS region (inherits from stackpanel.aws.roles-anywhere.region)";
    };

    account-id = lib.mkOption {
      type = lib.types.str;
      default = defaultAccountId;
      description = "AWS account ID (inherits from stackpanel.aws.roles-anywhere.account-id)";
    };

    # KMS configuration
    kms = {
      alias = lib.mkOption {
        type = lib.types.str;
        default = "${projectName}-secrets";
        description = "KMS key alias (without 'alias/' prefix)";
      };

      deletion-window-days = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Number of days before KMS key deletion (7-30)";
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
        description = "Additional managed policy ARNs to attach to the role";
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
          description = "GitHub organization name";
        };

        repo = lib.mkOption {
          type = lib.types.str;
          default = defaultGithubRepo;
          description = "GitHub repository name (or * for all repos in org)";
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

    # SSM configuration for secrets group keys
    ssm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable SSM Parameter Store IAM policies for secrets group key storage.
          When enabled, the IAM role gets ssm:GetParameter and ssm:PutParameter
          permissions for the group key paths.
        '';
      };

      key-prefix = lib.mkOption {
        type = lib.types.str;
        default = ssmKeyPrefix;
        description = ''
          SSM path prefix for group AGE keys.
          Default: /{chamber.service-prefix}/keys
          The IAM policy grants access to {key-prefix}/*
        '';
      };

      additional-paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Additional SSM parameter paths to grant access to.
          These are added alongside the group key paths.
          Supports wildcards (e.g., "/my-app/secrets/*").
        '';
      };
    };

    # Output sync configuration
    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "roleArn"
        "roleName"
        "kmsKeyArn"
        "kmsKeyId"
        "kmsAliasName"
        "oidcProviderArn"
      ];
      description = "Which outputs to sync to the storage backend";
    };
  };

  # ============================================================================
  # Config: register in infra.modules
  # ============================================================================
  config = lib.mkIf cfg.enable {
    # Auto-enable the infra system when this module is active
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.aws-secrets = {
      name = "AWS Secrets Infrastructure";
      description = "OIDC provider, IAM role, and KMS key for secrets management";
      path = ./module;
      inputs = {
        region = cfg.region;
        accountId = cfg.account-id;
        projectName = projectName;
        kms = {
          alias = cfg.kms.alias;
          deletionWindowDays = cfg.kms.deletion-window-days;
        };
        iam = {
          roleName = cfg.iam.role-name;
          additionalPolicies = cfg.iam.additional-policies;
        };
        oidc = {
          provider = cfg.oidc.provider;
          githubActions = {
            org = cfg.oidc.github-actions.org;
            repo = cfg.oidc.github-actions.repo;
            branch = cfg.oidc.github-actions.branch;
          };
          flyio = {
            orgId = cfg.oidc.flyio.org-id;
            appName = cfg.oidc.flyio.app-name;
          };
          rolesAnywhere = {
            trustAnchorArn = cfg.oidc.roles-anywhere.trust-anchor-arn;
          };
        };
        ssm = {
          enable = cfg.ssm.enable;
          keyPrefix = cfg.ssm.key-prefix;
          additionalPaths = cfg.ssm.additional-paths;
          groupPaths = groupSsmPaths;
        };
      };
      dependencies = {
        "@aws-sdk/client-sts" = "catalog:"; # AccountId from alchemy/aws
        "@aws-sdk/client-iam" = "catalog:"; # Role, GitHubOIDCProvider
        "@aws-sdk/client-kms" = "catalog:"; # KmsKey, KmsAlias
        "@aws-sdk/client-ssm" = "catalog:"; # SSM for group key storage
      };
      outputs =
        let
          # Build output declarations — all default to sync=true if in sync-outputs list
          mkOutput = key: desc: {
            description = desc;
            sensitive = false;
            sync = builtins.elem key cfg.sync-outputs;
          };
        in
        {
          roleArn = mkOutput "roleArn" "IAM role ARN for OIDC authentication";
          roleName = mkOutput "roleName" "IAM role name";
          kmsKeyArn = mkOutput "kmsKeyArn" "KMS key ARN for secrets encryption";
          kmsKeyId = mkOutput "kmsKeyId" "KMS key ID";
          kmsAliasName = mkOutput "kmsAliasName" "KMS key alias name";
          oidcProviderArn = mkOutput "oidcProviderArn" "OIDC provider ARN";
        };
    };
  };
}
