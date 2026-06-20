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
        example = 443;
      };

      to-port = lib.mkOption {
        type = lib.types.int;
        description = "End port for the rule.";
        example = 443;
      };

      protocol = lib.mkOption {
        type = lib.types.str;
        default = "tcp";
        description = "Protocol for the rule (tcp, udp, -1).";
        example = "tcp";
      };

      cidr-blocks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "IPv4 CIDR blocks for the rule.";
        example = [ "0.0.0.0/0" ];
      };

      ipv6-cidr-blocks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "IPv6 CIDR blocks for the rule.";
        example = [ "::/0" ];
      };

      security-group-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Source/target security group IDs for the rule.";
        example = [ "sg-0123456789abcdef0" ];
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional rule description.";
        example = "Allow HTTPS from the internet";
      };
    };
  };

  groupType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Security group name.";
        example = "web-public";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Security group description.";
        example = "Public web ingress";
      };

      ingress = lib.mkOption {
        type = lib.types.listOf ruleType;
        default = [ ];
        description = "Ingress rules.";
        example = [
          {
            from-port = 443;
            to-port = 443;
            cidr-blocks = [ "0.0.0.0/0" ];
          }
        ];
      };

      egress = lib.mkOption {
        type = lib.types.listOf ruleType;
        default = [ ];
        description = "Egress rules.";
        example = [
          {
            from-port = 0;
            to-port = 0;
            protocol = "-1";
            cidr-blocks = [ "0.0.0.0/0" ];
          }
        ];
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the security group.";
        example = { Environment = "prod"; };
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
      example = true;
    };

    vpc-id = lib.mkOption {
      type = lib.types.str;
      description = "VPC ID for security groups.";
      example = "vpc-0123456789abcdef0";
    };

    groups = lib.mkOption {
      type = lib.types.listOf groupType;
      default = [ ];
      description = "Security group definitions.";
      example = [
        {
          name = "web-public";
          ingress = [
            {
              from-port = 443;
              to-port = 443;
              cidr-blocks = [ "0.0.0.0/0" ];
            }
          ];
        }
      ];
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "groupIds" ];
      description = "Which outputs to sync to the storage backend.";
      example = [ "groupIds" ];
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
        inherit (cfg) groups;
      };
      dependencies = {
        "@aws-sdk/client-ec2" = "^3.953.0";
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
