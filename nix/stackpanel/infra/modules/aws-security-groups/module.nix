# ==============================================================================
# infra/modules/aws-security-groups/module.nix
#
# AWS Security Group provisioning module.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.aws-security-groups;

  ruleType = lib.types.submodule {
    options = {
      from-port = lib.mkOption {
        type = lib.types.int;
        description = "Start port for the rule.";
      };

      to-port = lib.mkOption {
        type = lib.types.int;
        description = "End port for the rule.";
      };

      protocol = lib.mkOption {
        type = lib.types.str;
        default = "tcp";
        description = "Protocol for the rule (tcp, udp, -1).";
      };

      cidr-blocks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "IPv4 CIDR blocks for the rule.";
      };

      ipv6-cidr-blocks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "IPv6 CIDR blocks for the rule.";
      };

      security-group-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Source/target security group IDs for the rule.";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional rule description.";
      };
    };
  };

  groupType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Security group name.";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Security group description.";
      };

      ingress = lib.mkOption {
        type = lib.types.listOf ruleType;
        default = [ ];
        description = "Ingress rules.";
      };

      egress = lib.mkOption {
        type = lib.types.listOf ruleType;
        default = [ ];
        description = "Egress rules.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the security group.";
      };
    };
  };
in
{
  options.stackpanel.infra.aws-security-groups = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AWS security group provisioning.";
    };

    vpc-id = lib.mkOption {
      type = lib.types.str;
      description = "VPC ID for security groups.";
    };

    groups = lib.mkOption {
      type = lib.types.listOf groupType;
      default = [ ];
      description = "Security group definitions.";
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "groupIds" ];
      description = "Which outputs to sync to the storage backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.aws-security-groups = {
      name = "AWS Security Groups";
      description = "Provision security groups in a VPC";
      path = ./index.ts;
      inputs = {
        vpcId = cfg.vpc-id;
        groups = cfg.groups;
      };
      dependencies = {
        "@aws-sdk/client-ec2" = "catalog:";
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
          groupIds = mkOutput "groupIds" "Security group IDs (JSON)";
        };
    };
  };
}
