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
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  messages = {
    # Root AWS configuration
    Aws = proto.mkMessage {
      name = "Aws";
      description = "AWS configuration including Roles Anywhere for certificate-based authentication";
      fields = {
        roles_anywhere = proto.message "RolesAnywhere" 1 "AWS Roles Anywhere configuration";
      };
    };

    # AWS Roles Anywhere configuration
    RolesAnywhere = proto.mkMessage {
      name = "RolesAnywhere";
      description = "AWS Roles Anywhere configuration for certificate-based authentication";
      fields = {
        enable = proto.bool 1 "Enable AWS Roles Anywhere cert auth";
        region = proto.string 2 "AWS region";
        account_id = proto.string 3 "AWS account ID";
        role_name = proto.string 4 "IAM role name to assume";
        trust_anchor_arn = proto.string 5 "AWS Roles Anywhere trust anchor ARN";
        profile_arn = proto.string 6 "AWS Roles Anywhere profile ARN";
        cache_buffer_seconds = proto.string 7 "Seconds before expiry to refresh cached credentials";
        prompt_on_shell = proto.bool 8 "Prompt for AWS cert-auth setup on shell entry if not configured";
      };
    };
  };
}
