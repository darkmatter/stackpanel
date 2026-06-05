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
      type = "PANEL_TYPE_STATUS";
      order = 100;
      fields = [
        {
          name = "metrics";
          type = "FIELD_TYPE_STRING";
          value = builtins.toJSON [
            {
              label = "AWS Profile";
              value = cfg.profile;
              status = "ok";
            }
            {
              label = "AWS CLI Wrapper";
              value = if cfg.awscliWrapper.enable then "enabled" else "disabled";
              status = if cfg.awscliWrapper.enable then "ok" else "warning";
            }
            {
              label = "OpenTofu Wrapper";
              value = if cfg.opentofuWrapper.enable then "enabled" else "disabled";
              status = if cfg.opentofuWrapper.enable then "ok" else "warning";
            }
            {
              label = "Terraform Wrapper";
              value = if cfg.terraformWrapper.enable then "enabled" else "disabled";
              status = if cfg.terraformWrapper.enable then "ok" else "warning";
            }
          ];
        }
      ];
    };
  };
}
