# ==============================================================================
# aws.nix
#
# AWS Roles Anywhere certificate authentication options.
#
# Configures AWS Roles Anywhere for certificate-based authentication,
# allowing devenv shells to assume IAM roles without long-lived credentials.
#
# Options:
#   - enable: Enable AWS Roles Anywhere cert auth
#   - region: AWS region
#   - account-id: AWS account ID
#   - role-name: IAM role name to assume
#   - trust-anchor-arn: AWS Roles Anywhere trust anchor ARN
#   - profile-arn: AWS Roles Anywhere profile ARN
#   - cache-buffer-seconds: Seconds before expiry to refresh credentials
#   - prompt-on-shell: Prompt for setup on shell entry if not configured
#
# Requires Step CA certificates to be configured via stackpanel.network.step.
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.aws.roles-anywhere = {
    enable = lib.mkEnableOption "AWS Roles Anywhere cert auth";

    region = lib.mkOption {
      type = lib.types.str;
      default = "us-west-2";
      description = "AWS region";
    };

    account-id = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "AWS account ID";
    };

    role-name = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "IAM role name to assume";
    };

    trust-anchor-arn = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "AWS Roles Anywhere trust anchor ARN";
    };

    profile-arn = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "AWS Roles Anywhere profile ARN";
    };

    cache-buffer-seconds = lib.mkOption {
      type = lib.types.str;
      default = "300";
      description = "Seconds before expiry to refresh cached credentials";
    };

    prompt-on-shell = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prompt for AWS cert-auth setup on shell entry if not configured";
    };
  };
}
