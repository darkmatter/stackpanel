# ==============================================================================
# sst/default.nix
#
# SST infrastructure provisioning module for stackpanel.
#
# This module provides:
#   - KMS key creation for secrets encryption/decryption
#   - IAM role with OIDC-based authentication
#   - Support for multiple OIDC providers (GitHub Actions, Fly.io, Roles Anywhere)
#   - SST config file generation
#
# Usage:
#   stackpanel.sst = {
#     enable = true;
#     project-name = "my-project";
#     region = "us-west-2";
#     kms.enable = true;
#     oidc.provider = "github-actions";
#     oidc.github-actions = { org = "my-org"; repo = "my-repo"; };
#   };
# ==============================================================================
{ ... }:
{
  imports = [
    ./sst.nix
  ];
}
