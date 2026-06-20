# ==============================================================================
# aws.proto.nix
#
# Protobuf schema for AWS configuration.
# Configures AWS Roles Anywhere for certificate-based authentication.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "aws.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # aws.nix - AWS configuration
    # type: stackpanel.aws
    # See: https://stackpanel.dev/docs/aws
    {
      # roles-anywhere = {
      #   enable = true;
      #   region = "us-east-1";
      #   account-id = "123456789012";
      #   role-name = "DeveloperRole";
      #   trust-anchor-arn = "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/...";
      #   profile-arn = "arn:aws:rolesanywhere:us-east-1:123456789012:profile/...";
      #   cache-buffer-seconds = "300";
      #   prompt-on-shell = true;
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    # Root AWS configuration
    Aws = proto.mkMessage {
      name = "Aws";
      description = "AWS configuration including Roles Anywhere for certificate-based authentication";
      fields = {
        roles_anywhere = proto.withExample {
          enable = true;
          region = "us-east-1";
          "account-id" = "123456789012";
          "role-name" = "StackpanelDeveloper";
        } (proto.message "RolesAnywhere" 1 ''
          AWS Roles Anywhere certificate auth profile used to assume IAM roles
          without long-lived access keys.
        '');
        default_profile = proto.withExample "default" (
          proto.string 2 "AWS CLI profile name written as the default profile for generated config"
        );
        extra_config = proto.withExample "[profile dev]\nregion = us-east-1" (
          proto.string 3 "Raw INI snippet appended to generated AWS config for extra profiles or service settings"
        );
      };
    };

    # AWS Roles Anywhere configuration
    RolesAnywhere = proto.mkMessage {
      name = "RolesAnywhere";
      description = "AWS Roles Anywhere configuration for certificate-based authentication";
      fields = {
        enable = proto.withExample true (proto.bool 1 "Enable AWS Roles Anywhere certificate-based auth for this workspace");
        region = proto.withExample "us-east-1" (proto.string 2 "AWS region containing the Roles Anywhere trust anchor and profile");
        account_id = proto.withExample "123456789012" (proto.string 3 "AWS account ID that owns the IAM role and Roles Anywhere resources");
        role_name = proto.withExample "StackpanelDeveloper" (proto.string 4 "IAM role name to assume with the local device certificate");
        trust_anchor_arn = proto.withExample "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/abcd1234" (
          proto.string 5 "AWS Roles Anywhere trust anchor ARN linked to the Step CA or external CA root"
        );
        profile_arn = proto.withExample "arn:aws:rolesanywhere:us-east-1:123456789012:profile/efgh5678" (
          proto.string 6 "AWS Roles Anywhere profile ARN that permits assuming role-name"
        );
        cache_buffer_seconds = proto.withExample "300" (
          proto.string 7 "Seconds before credential expiry when cached credentials should be refreshed"
        );
        prompt_on_shell = proto.withExample true (
          proto.bool 8 "Prompt for AWS certificate-auth setup on shell entry when required files or config are missing"
        );
      };
    };
  };
}
