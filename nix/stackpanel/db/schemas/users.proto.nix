# ==============================================================================
# users.proto.nix
#
# Protobuf schema for users configuration.
#
# Users are team members with project access. Note that secrets are now
# encrypted using master keys (stackpanel.secrets.master-keys), not
# per-user keys.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "users.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # users.nix - Team members with project access
    # type: sp-user
    # See: https://stackpanel.dev/docs/users
    {
      # Example user:
      # johndoe = {
      #   name = "John Doe";
      #   github = "johndoe";
      #   email = "john@example.com";
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = { };

  messages = {
    User = proto.mkMessage {
      name = "User";
      description = "A team member with access to the project";
      fields = {
        name = proto.string 1 "Display name of the user";
        github = proto.optional (proto.string 2 "GitHub username");
        email = proto.optional (proto.string 3 "Email address");
        public-keys = proto.repeated (proto.string 4 "SSH or AGE public keys for the user");
        secrets-allowed-environments = proto.repeated (proto.string 5 "Environments this user can access secrets for (e.g., dev, staging, production)");
      };
    };

    Users = proto.mkMessage {
      name = "Users";
      description = "Map of username to user configuration";
      fields = {
        users = proto.map "string" "User" 1 "Map of username to user config";
      };
    };
  };
}
