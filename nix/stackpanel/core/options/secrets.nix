# ==============================================================================
# secrets.nix
#
# Secrets management options - SOPS-encrypted secrets with codegen.
#
# This module imports options from the proto schema (db/schemas/secrets.proto.nix)
# and extends them with Nix-specific runtime options like packages.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
# ==============================================================================
{ lib, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };
in
{
  # Secrets options derived from proto schema
  # The proto defines: enable, input_directory, environments, codegen
  # These are converted to kebab-case: input-directory
  options.stackpanel.secrets = db.extend.secrets // {
    # Nix-specific extension: generated packages (not in data schema)
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = "Generated script packages (for standalone/flake users).";
      internal = true;
    };
  };
}
