{ lib, config, ... }:

let
  meta = import ./meta.nix;
  cfg = config.stackpanel.aws-vault;
  sp = config.stackpanel;
in
{
  config = lib.mkIf (sp.enable && cfg.enable) {
    stackpanel.panels."${meta.id}-status" = {
      module = meta.id;
      title = "AWS Vault";
      description = "AWS Vault configuration and wrapper status";
      type = "status";
      order = 100;
      fields = {
        profile = {
          label = "AWS Profile";
          type = "FIELD_TYPE_STRING";
          value = cfg.profile;
          description = "The active AWS profile";
        };
        awscliWrapper = {
          label = "AWS CLI Wrapper";
          type = "FIELD_TYPE_BOOLEAN";
          value = cfg.awscliWrapper.enable;
          description = "Whether the AWS CLI is wrapped with aws-vault";
        };
        opentofuWrapper = {
          label = "OpenTofu Wrapper";
          type = "FIELD_TYPE_BOOLEAN";
          value = cfg.opentofuWrapper.enable;
          description = "Whether OpenTofu is wrapped with aws-vault";
        };
        terraformWrapper = {
          label = "Terraform Wrapper";
          type = "FIELD_TYPE_BOOLEAN";
          value = cfg.terraformWrapper.enable;
          description = "Whether Terraform is wrapped with aws-vault";
        };
      };
    };
  };
}
