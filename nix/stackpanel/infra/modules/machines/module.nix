# ==============================================================================
# infra/modules/machines/module.nix
#
# Machine inventory infra module.
#
# Accepts a machine inventory definition in Nix and emits a JSON string
# output that can be stored via the infra output backend. Colmena consumes
# this inventory from stackpanel.infra.outputs.machines.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.machines;

  sshConfigType = lib.types.submodule {
    options = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user for connecting to the machine.";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 22;
        description = "SSH port for connecting to the machine.";
      };

      keyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the SSH private key for this machine.";
      };
    };
  };

  awsFilterType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "EC2 filter name (e.g., instance-state-name, tag:Name).";
      };

      values = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Values for the EC2 filter.";
      };
    };
  };

  machineType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional machine identifier (defaults to the attrset key).";
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-friendly machine name.";
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SSH host or hostname for the machine.";
      };

      ssh = lib.mkOption {
        type = sshConfigType;
        default = { };
        description = "SSH connection settings for the machine.";
      };

      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tags used for grouping and target selection.";
      };

      roles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Roles associated with this machine.";
      };

      provider = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Infrastructure provider name (aws, gcp, hetzner, etc.).";
      };

      arch = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Target system architecture (e.g., x86_64-linux).";
      };

      publicIp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public IPv4/IPv6 address for the machine.";
      };

      privateIp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Private IPv4/IPv6 address for the machine.";
      };

      labels = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Arbitrary labels attached to the machine.";
      };

      nixosProfile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "NixOS profile name to deploy on this machine.";
      };

      nixosModules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra NixOS modules to include for this machine.";
      };

      targetEnv = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Deployment environment label for this machine.";
      };

      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Environment variables applied to this machine.";
      };

      metadata = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Extra metadata for downstream tooling.";
      };
    };
  };
in
{
  options.stackpanel.infra.machines = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable machine inventory provisioning via infra.";
    };

    source = lib.mkOption {
      type = lib.types.enum [
        "static"
        "aws-ec2"
      ];
      default = "static";
      description = "Machine inventory source (static or AWS EC2).";
    };

    aws = {
      region = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = config.stackpanel.aws.roles-anywhere.region or null;
        description = "AWS region for EC2 inventory (falls back to AWS env defaults).";
      };

      instance-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Explicit EC2 instance IDs to include in inventory.";
      };

      filters = lib.mkOption {
        type = lib.types.listOf awsFilterType;
        default = [
          {
            name = "instance-state-name";
            values = [ "running" ];
          }
        ];
        description = "EC2 filters for inventory discovery.";
      };

      name-tag-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "Name" ];
        description = "Tag keys used to derive machine names.";
      };

      role-tag-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "stackpanel:role"
          "role"
        ];
        description = "Tag keys used to derive machine roles.";
      };

      tag-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "stackpanel:tag"
          "tag"
        ];
        description = "Tag keys used to derive machine tags.";
      };

      env-tag-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "stackpanel:env"
          "env"
          "stage"
        ];
        description = "Tag keys used to derive machine target environments.";
      };

      host-preference = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [
          "publicDns"
          "publicIp"
          "privateIp"
        ]);
        default = [
          "publicDns"
          "publicIp"
          "privateIp"
        ];
        description = "Preferred host fields for connecting to EC2 machines.";
      };

      ssh = lib.mkOption {
        type = sshConfigType;
        default = { };
        description = "Default SSH settings for EC2 machines.";
      };
    };

    machines = lib.mkOption {
      type = lib.types.attrsOf machineType;
      default = { };
      description = "Machine inventory definitions to emit via infra outputs.";
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "machines" ];
      description = "Which outputs to sync to the storage backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.machines = {
      name = "Machine Inventory";
      description = "Machine inventory provider for Colmena deployments";
      path = ./index.ts;
      inputs = {
        source = cfg.source;
        machines = cfg.machines;
        aws = {
          region = cfg.aws.region;
          instanceIds = cfg.aws.instance-ids;
          filters = cfg.aws.filters;
          nameTagKeys = cfg.aws.name-tag-keys;
          roleTagKeys = cfg.aws.role-tag-keys;
          tagKeys = cfg.aws.tag-keys;
          envTagKeys = cfg.aws.env-tag-keys;
          hostPreference = cfg.aws.host-preference;
          ssh = {
            user = cfg.aws.ssh.user;
            port = cfg.aws.ssh.port;
            keyPath = cfg.aws.ssh.keyPath;
          };
        };
      };
      dependencies = lib.optionalAttrs (cfg.source == "aws-ec2") {
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
          machines = mkOutput "machines" "Machine inventory (JSON)";
        };
    };
  };
}
