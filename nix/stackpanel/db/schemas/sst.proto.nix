# ==============================================================================
# sst.proto.nix
#
# Protobuf schema for SST infrastructure configuration.
# Configures AWS infrastructure provisioning with KMS and OIDC.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "sst.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # sst.nix - SST infrastructure configuration
    # type: stackpanel.sst
    # See: https://stackpanel.dev/docs/sst
    {
      # enable = true;
      # project-name = "my-project";
      # region = "us-west-2";
      # account-id = "123456789012";
      # config-path = "infra/sst/sst.config.ts";
      #
      # kms = {
      #   enable = true;
      #   alias = "my-project-secrets";
      # };
      #
      # oidc = {
      #   provider = "github-actions";  # or "flyio" or "roles-anywhere"
      #   github-actions = {
      #     org = "my-org";
      #     repo = "*";
      #   };
      # };
      #
      # iam = {
      #   role-name = "my-project-secrets-role";
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  messages = {
    # Root SST configuration
    Sst = proto.mkMessage {
      name = "Sst";
      description = "SST infrastructure configuration for AWS provisioning";
      fields = {
        enable = proto.bool 1 "Enable SST infrastructure provisioning";
        project_name = proto.string 2 "SST project name";
        region = proto.string 3 "AWS region";
        account_id = proto.string 4 "AWS account ID";
        config_path = proto.string 5 "Path to generate sst.config.ts";
        kms = proto.message "SstKms" 6 "KMS configuration";
        oidc = proto.message "SstOidc" 7 "OIDC provider configuration";
        iam = proto.message "SstIam" 8 "IAM configuration";
      };
    };

    # KMS configuration
    SstKms = proto.mkMessage {
      name = "SstKms";
      description = "KMS key configuration for secrets encryption";
      fields = {
        enable = proto.bool 1 "Create a KMS key for secrets";
        alias = proto.string 2 "KMS key alias";
        deletion_window_days = proto.int32 3 "Days before key deletion";
      };
    };

    # OIDC configuration
    SstOidc = proto.mkMessage {
      name = "SstOidc";
      description = "OIDC provider configuration for IAM role assumption";
      fields = {
        provider = proto.string 1 "OIDC provider type (github-actions, flyio, roles-anywhere)";
        github_actions = proto.message "SstGithubActions" 2 "GitHub Actions OIDC settings";
        flyio = proto.message "SstFlyio" 3 "Fly.io OIDC settings";
        roles_anywhere = proto.message "SstRolesAnywhere" 4 "Roles Anywhere settings";
      };
    };

    # GitHub Actions OIDC
    SstGithubActions = proto.mkMessage {
      name = "SstGithubActions";
      description = "GitHub Actions OIDC configuration";
      fields = {
        org = proto.string 1 "GitHub organization";
        repo = proto.string 2 "GitHub repository (or * for all)";
      };
    };

    # Fly.io OIDC
    SstFlyio = proto.mkMessage {
      name = "SstFlyio";
      description = "Fly.io OIDC configuration";
      fields = {
        org_id = proto.string 1 "Fly.io organization ID";
        app_name = proto.string 2 "Fly.io app name (or * for all)";
      };
    };

    # Roles Anywhere
    SstRolesAnywhere = proto.mkMessage {
      name = "SstRolesAnywhere";
      description = "AWS Roles Anywhere configuration";
      fields = {
        trust_anchor_arn = proto.string 1 "Trust anchor ARN";
      };
    };

    # IAM configuration
    SstIam = proto.mkMessage {
      name = "SstIam";
      description = "IAM role configuration";
      fields = {
        role_name = proto.string 1 "IAM role name";
      };
    };
  };
}
