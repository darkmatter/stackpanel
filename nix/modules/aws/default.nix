# AWS module - Roles Anywhere cert-based authentication
# Standalone module - no flake-parts dependency
#
# Usage:
#   stackpanel.aws.certAuth = {
#     enable = true;
#     accountId = "123456789";
#     roleName = "my-role";
#     trustAnchorArn = "arn:aws:rolesanywhere:...";
#     profileArn = "arn:aws:rolesanywhere:...";
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.aws.certAuth;
  stackpanelCfg = config.stackpanel;

  # Import shared AWS library
  awsLib = import ../../lib/aws.nix {inherit pkgs lib;};

  # Create scripts using shared library
  awsScripts = awsLib.mkAwsCredScripts {
    inherit
      (cfg)
      stateDir
      accountId
      roleName
      trustAnchorArn
      profileArn
      region
      cacheBufferSeconds
      ;
  };
in {
  options.stackpanel.aws.certAuth = {
    enable = lib.mkEnableOption "AWS Roles Anywhere cert auth";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${stackpanelCfg.stateDir}/aws";
      description = "Directory for AWS state (certs, creds cache)";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "us-west-2";
      description = "AWS region";
    };

    accountId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "AWS account ID";
    };

    roleName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "IAM role name to assume";
    };

    trustAnchorArn = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "AWS Roles Anywhere trust anchor ARN";
    };

    profileArn = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "AWS Roles Anywhere profile ARN";
    };

    cacheBufferSeconds = lib.mkOption {
      type = lib.types.str;
      default = "300";
      description = "Seconds before expiry to refresh cached credentials";
    };
  };

  config = lib.mkIf cfg.enable {
    # Export packages for use in devShells or other modules
    stackpanel.packages = {
      aws-creds-env = awsScripts.awsCredsEnv;
      aws-wrapped = awsScripts.awsCli;
    };
  };
}
