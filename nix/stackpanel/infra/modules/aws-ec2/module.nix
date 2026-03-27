# ==============================================================================
# infra/modules/aws-ec2/module.nix
#
# AWS EC2 instance provisioning module.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.aws-ec2;

  sshType = lib.types.submodule {
    options = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user for the instance.";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 22;
        description = "SSH port for the instance.";
      };

      key-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SSH private key path for the instance.";
      };
    };
  };

  machineMetaType = lib.types.submodule {
    options = {
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Machine tags for Colmena targeting.";
      };

      roles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Machine roles for Colmena targeting.";
      };

      target-env = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Deployment environment label for the machine.";
      };

      arch = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Target system architecture (e.g., x86_64-linux).";
      };

      ssh = lib.mkOption {
        type = sshType;
        default = { };
        description = "SSH settings for the instance.";
      };
    };
  };

  instanceType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Instance name.";
      };

      ami = lib.mkOption {
        type = lib.types.str;
        description = "AMI ID.";
      };

      instance-type = lib.mkOption {
        type = lib.types.str;
        default = "t3.micro";
        description = "EC2 instance type.";
      };

      subnet-id = lib.mkOption {
        type = lib.types.str;
        description = "Subnet ID for the instance.";
      };

      security-group-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Security group IDs for the instance.";
      };

      key-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "EC2 key pair name.";
      };

      iam-instance-profile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "IAM instance profile name.";
      };

      user-data = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User data script.";
      };

      root-volume-size = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Root volume size in GB.";
      };

      associate-public-ip = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Associate a public IP address.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the EC2 instance.";
      };

      machine = lib.mkOption {
        type = machineMetaType;
        default = { };
        description = "Machine metadata for Colmena.";
      };
    };
  };
in
{
  options.stackpanel.infra.aws-ec2 = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AWS EC2 instance provisioning.";
    };

    instances = lib.mkOption {
      type = lib.types.listOf instanceType;
      default = [ ];
      description = "EC2 instance definitions.";
    };

    defaults = lib.mkOption {
      type = instanceType;
      default = {
        name = "default";
        ami = "";
        instance-type = "t3.micro";
        subnet-id = "";
      };
      description = "Default values merged into each instance.";
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "instanceIds"
        "publicIps"
        "publicDns"
        "privateIps"
        "machines"
      ];
      description = "Which outputs to sync to the storage backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.aws-ec2 = {
      name = "AWS EC2";
      description = "Provision EC2 instances";
      path = ./index.ts;
      inputs = {
        defaults = cfg.defaults;
        instances = cfg.instances;
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
          instanceIds = mkOutput "instanceIds" "Instance IDs (JSON)";
          publicIps = mkOutput "publicIps" "Instance public IPs (JSON)";
          publicDns = mkOutput "publicDns" "Instance public DNS (JSON)";
          privateIps = mkOutput "privateIps" "Instance private IPs (JSON)";
          machines = mkOutput "machines" "Machine inventory (JSON)";
        };
    };
  };
}
