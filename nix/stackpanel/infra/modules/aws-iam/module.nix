# ==============================================================================
# infra/modules/aws-iam/module.nix
#
# AWS IAM role + instance profile module (EC2 oriented).
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.aws-iam;

  inlinePolicyType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Inline policy name.";
      };

      document = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        description = "IAM policy document (JSON object).";
      };
    };
  };
in
{
  options.stackpanel.infra.aws-iam = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AWS IAM role + instance profile provisioning.";
    };

    role = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "IAM role name.";
      };

      assume-role-policy = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
        default = null;
        description = "Optional assume role policy document (defaults to EC2 trust).";
      };

      managed-policy-arns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Managed policy ARNs to attach.";
      };

      inline-policies = lib.mkOption {
        type = lib.types.listOf inlinePolicyType;
        default = [ ];
        description = "Inline policies to attach to the role.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the IAM role.";
      };
    };

    instance-profile = {
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Instance profile name (defaults to role name + '-profile').";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the instance profile.";
      };
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "roleArn"
        "roleName"
        "instanceProfileArn"
        "instanceProfileName"
      ];
      description = "Which outputs to sync to the storage backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.aws-iam = {
      name = "AWS IAM";
      description = "IAM role and instance profile provisioning";
      path = ./index.ts;
      inputs = {
        role = {
          name = cfg.role.name;
          assumeRolePolicy = cfg.role.assume-role-policy;
          managedPolicyArns = cfg.role.managed-policy-arns;
          inlinePolicies = cfg.role.inline-policies;
          tags = cfg.role.tags;
        };
        instanceProfile = {
          name = cfg.instance-profile.name;
          tags = cfg.instance-profile.tags;
        };
      };
      dependencies = {
        "@aws-sdk/client-iam" = "^3.953.0";
      };
      outputs =
        let
          mkOutput = key: desc: {
            description = desc;
            sensitive = false;
            sync = builtins.elem key cfg.sync-outputs;
          };
        in
        {
          roleArn = mkOutput "roleArn" "IAM role ARN";
          roleName = mkOutput "roleName" "IAM role name";
          instanceProfileArn = mkOutput "instanceProfileArn" "Instance profile ARN";
          instanceProfileName = mkOutput "instanceProfileName" "Instance profile name";
        };
    };
  };
}
