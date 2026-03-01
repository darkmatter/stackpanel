# ==============================================================================
# infra/modules/aws-key-pairs/module.nix
#
# AWS Key Pair provisioning module.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.aws-key-pairs;

  keyType = lib.types.submodule {
    options = {
      public-key = lib.mkOption {
        type = lib.types.str;
        description = "Public key material for the key pair.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the key pair.";
      };

      destroy-on-delete = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Delete the key pair when running alchemy destroy.";
      };
    };
  };
in
{
  options.stackpanel.infra.aws-key-pairs = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AWS key pair provisioning.";
    };

    keys = lib.mkOption {
      type = lib.types.attrsOf keyType;
      default = { };
      description = "Key pair definitions keyed by key name.";
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "keyNames" "keyPairIds" ];
      description = "Which outputs to sync to the storage backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.aws-key-pairs = {
      name = "AWS Key Pairs";
      description = "Import or create EC2 key pairs";
      path = ./index.ts;
      inputs = {
        keys = cfg.keys;
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
          keyNames = mkOutput "keyNames" "Key pair names (JSON)";
          keyPairIds = mkOutput "keyPairIds" "Key pair IDs (JSON)";
        };
    };
  };
}
