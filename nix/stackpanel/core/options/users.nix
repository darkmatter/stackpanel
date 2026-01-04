# ==============================================================================
# users.nix
#
# User management options.
#
# This module imports options from the proto schema (db/schemas/users.proto.nix)
# and extends them with Nix-specific runtime options.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
# ==============================================================================
{ lib, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };

  # Get the base user options from proto schema
  # Proto defines: name, github, public_keys, secrets_allowed_environments
  # Converted to kebab-case: public-keys, secrets-allowed-environments
  baseUserOptions = db.extend.user;

  # Extended user options with Nix-specific runtime fields
  extendedUserOptions = baseUserOptions // {
    # Nix-specific extension: runtime-only admin flag (not persisted to data)
    is-admin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this user has admin privileges (computed at runtime)";
    };

    # Nix-specific extension: email for notifications
    email = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email address for notifications";
    };
  };

  # Build the extended submodule type
  extendedUserType = lib.types.submodule { options = extendedUserOptions; };
in
{
  options.stackpanel.users = lib.mkOption {
    description = ''
      Users of the repository who should have access to secrets.

      Base schema: nix/stackpanel/db/schemas/users.proto.nix
      Extended with: is-admin, email
    '';
    example = {
      cooper = {
        name = "Cooper Maruyama";
        github = "coopermaruyama";
        email = "cooper@example.com";
        is-admin = true;
        secrets-allowed-environments = [
          "dev"
          "staging"
          "production"
        ];
        public-keys = [
          "age1..."
          "ssh-ed25519 AAAA..."
        ];
      };
      alice = {
        name = "Alice Example";
        github = "aliceexample";
        secrets-allowed-environments = [ "dev" ];
        public-keys = [ "age1..." ];
      };
    };
    type = lib.types.attrsOf extendedUserType;
    default = { };
  };

  options.stackpanel.users-settings = {
    disable-github-sync = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable automatic GitHub public key synchronization for users with GitHub usernames.";
    };
  };
}
