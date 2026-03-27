# ==============================================================================
# users.nix
#
# User management options.
#
# This module imports options from the proto schema (db/schemas/users.proto.nix)
# and extends them with Nix-specific runtime options.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
#
# Note: Secrets are encrypted using master keys (stackpanel.secrets.master-keys),
# not per-user keys.
# ==============================================================================
{ lib, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../db { inherit lib; };

  # User submodule using proto-derived options
  userModule =
    { ... }:
    {
      # Base options from proto schema (name, github, email)
      # No additional extensions needed - proto covers everything
      options = db.mkOpt db.extend.user { };
    };
in
{
  options.stackpanel.users = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule userModule);
    default = { };
    description = ''
      Team members with project access.

      Note: Secrets are encrypted using master keys, not per-user keys.
      See stackpanel.secrets.master-keys for encryption configuration.
    '';
    example = lib.literalExpression ''
      {
        johndoe = {
          name = "John Doe";
          github = "johndoe";
          email = "john@example.com";
        };
        alice = {
          name = "Alice Example";
          github = "aliceexample";
        };
      }
    '';
  };
}
