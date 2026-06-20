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
  inherit (import ../../../../lib/mkInfraModule.nix { inherit lib; }) mkInfraModule;

  keyType = lib.types.submodule {
    options = {
      public-key = lib.mkOption {
        type = lib.types.str;
        description = "Public key material for the key pair.";
        example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@example.com";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the key pair.";
        example = { Environment = "prod"; };
      };

      destroy-on-delete = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Delete the key pair when running alchemy destroy.";
        example = false;
      };
    };
  };
in
mkInfraModule {
  id = "aws-key-pairs";
  name = "AWS Key Pairs";
  description = "Import or create EC2 key pairs";
  path = ./index.ts;
  inherit config;

  options = {
    keys = lib.mkOption {
      type = lib.types.attrsOf keyType;
      default = { };
      description = "Key pair definitions keyed by key name.";
      example = {
        deploy = {
          public-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... deploy@example.com";
        };
      };
    };
  };

  inputs = cfg: {
    inherit (cfg) keys;
  };

  dependencies = {
    "@aws-sdk/client-ec2" = "catalog:";
  };

  outputs = {
    keyNames = "Key pair names (JSON)";
    keyPairIds = "Key pair IDs (JSON)";
  };
}
