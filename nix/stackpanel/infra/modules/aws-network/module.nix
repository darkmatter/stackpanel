# ==============================================================================
# infra/modules/aws-network/module.nix
#
# AWS network discovery module (default VPC + subnets).
#
# Discovers VPC and subnet IDs and exposes them as infra outputs for use
# in downstream modules.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.aws-network;
in
{
  options.stackpanel.infra.aws-network = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AWS network discovery (VPC + subnets).";
    };

    region = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.stackpanel.aws.roles-anywhere.region or null;
      description = "AWS region for network discovery (defaults to AWS env).";
    };

    vpc = {
      id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional VPC ID to use (otherwise discover default VPC).";
      };

      use-default = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use the AWS default VPC when no VPC ID is provided.";
      };
    };

    subnets = {
      ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Optional subnet IDs to use (otherwise discover from VPC).";
      };

      use-default = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Discover subnets from the resolved VPC when no IDs are provided.";
      };
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "vpcId" "subnetIds" ];
      description = "Which outputs to sync to the storage backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.aws-network = {
      name = "AWS Network";
      description = "Discover default VPC and subnet IDs";
      path = ./index.ts;
      inputs = {
        region = cfg.region;
        vpc = {
          id = cfg.vpc.id;
          useDefault = cfg.vpc.use-default;
        };
        subnets = {
          ids = cfg.subnets.ids;
          useDefault = cfg.subnets.use-default;
        };
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
          vpcId = mkOutput "vpcId" "Resolved VPC ID";
          subnetIds = mkOutput "subnetIds" "Resolved subnet IDs (JSON)";
          subnetAzs = mkOutput "subnetAzs" "Resolved subnet AZs (JSON)";
        };
    };
  };
}
