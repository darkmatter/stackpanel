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
        roles_anywhere = proto.message "RolesAnywhere" 1 "AWS Roles Anywhere configuration";
        default_profile = proto.withExample "default" (proto.string 2 "AWS profile name to use as default (default: 'default')");
        extra_config = proto.withExample "[profile dev]\nregion = us-east-1" (proto.string 3 "Additional AWS config to append (raw INI format)");
      };
    };

    # AWS Roles Anywhere configuration
    RolesAnywhere = proto.mkMessage {
      name = "RolesAnywhere";
      description = "AWS Roles Anywhere configuration for certificate-based authentication";
      fields = {
        enable = proto.withExample true (proto.bool 1 "Enable AWS Roles Anywhere cert auth");
        region = proto.withExample "us-east-1" (proto.string 2 "AWS region");
        account_id = proto.withExample "123456789012" (proto.string 3 "AWS account ID");
        role_name = proto.withExample "DeveloperRole" (proto.string 4 "IAM role name to assume");
        trust_anchor_arn = proto.withExample "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/abcd1234" (proto.string 5 "AWS Roles Anywhere trust anchor ARN");
        profile_arn = proto.withExample "arn:aws:rolesanywhere:us-east-1:123456789012:profile/efgh5678" (proto.string 6 "AWS Roles Anywhere profile ARN");
        cache_buffer_seconds = proto.withExample "300" (proto.string 7 "Seconds before expiry to refresh cached credentials");
        prompt_on_shell = proto.withExample true (proto.bool 8 "Prompt for AWS cert-auth setup on shell entry if not configured");
      };
    };
  };
}
