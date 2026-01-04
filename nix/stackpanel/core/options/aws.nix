# ==============================================================================
# aws.nix
#
# AWS Roles Anywhere certificate authentication options.
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
  # AWS options derived from proto schema
  # The proto defines: enable, region, account_id, role_name, trust_anchor_arn,
  # profile_arn, cache_buffer_seconds, prompt_on_shell
  # These are converted to kebab-case: account-id, role-name, etc.
  options.stackpanel.aws.roles-anywhere = db.extend.aws;
}
