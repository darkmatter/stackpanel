# ==============================================================================
# services/aws/options.nix
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
      description = "AWS profile name to use as default. Empty string means 'default'.";
    };

    extra-config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Additional AWS config to append (raw INI format).
        Use this to define extra profiles or settings.

        Example:
          extra-config = '''
            [profile production]
            region = us-east-1
            role_arn = arn:aws:iam::123456789012:role/ProdRole
            source_profile = default
          ''';
      '';
    };

    # AWS Roles Anywhere options derived from proto schema
    # The proto defines: enable, region, account_id, role_name, trust_anchor_arn,
    # profile_arn, cache_buffer_seconds, prompt_on_shell
    # These are converted to kebab-case: account-id, role-name, etc.
    roles-anywhere = db.asOptions db.extend.aws;
  };
}
