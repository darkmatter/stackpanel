# ==============================================================================
# users.proto.nix
#
# Protobuf schema for users configuration.
# This generates a .proto file that buf can use to create Go, TypeScript,
# Drizzle schemas, tRPC definitions, etc.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "users.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  enums = {
    Environment = proto.mkEnum {
      name = "Environment";
      description = "Environments a user can access secrets for";
      values = [
        "ENVIRONMENT_UNSPECIFIED"
        "ENVIRONMENT_DEV"
        "ENVIRONMENT_STAGING"
        "ENVIRONMENT_PRODUCTION"
      ];
    };
  };

  messages = {
    User = proto.mkMessage {
      name = "User";
      description = "A team member with access to the project";
      fields = {
        name = proto.string 1 "Display name of the user";
        github = proto.optional (proto.string 2 "GitHub username");
        public_keys = proto.repeated (proto.string 3 "SSH or AGE public keys for encryption");
        secrets_allowed_environments = proto.repeated (
          proto.message "Environment" 4 "Environments this user can access secrets for"
        );
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
