# ==============================================================================
# aws.nix
#
# AWS configuration options including Roles Anywhere certificate authentication.
#
# This module imports options from the proto schema (db/schemas/aws.proto.nix)
# and extends them with any Nix-specific runtime options.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
# ==============================================================================
{ lib, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };
in
{
  options.stackpanel.aws = {
    # Root-level AWS options
    default-profile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        AWS profile name written as the default credential_process profile.

        Empty string means "default". Set this when the workspace should expose
        Roles Anywhere credentials through a named AWS CLI/SDK profile instead.
      '';
      example = "stackpanel-dev";
    };

    extra-config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Additional AWS config appended to the generated AWS config file in raw
        INI format.

        Use this for derived profiles, role chains, SSO-adjacent settings, or
        service-specific defaults that should live next to the generated Roles
        Anywhere profile.
      '';
      example = ''
        [profile production]
        region = us-east-1
        role_arn = arn:aws:iam::123456789012:role/ProdRole
        source_profile = stackpanel-dev
      '';
    };

    # AWS Roles Anywhere options derived from proto schema
    # The proto defines: enable, region, account_id, role_name, trust_anchor_arn,
    # profile_arn, cache_buffer_seconds, prompt_on_shell
    # These are converted to kebab-case: account-id, role-name, etc.
    roles-anywhere = db.asOptions db.extend.aws;
  };
}
