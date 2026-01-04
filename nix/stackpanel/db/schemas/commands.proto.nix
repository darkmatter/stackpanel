# ==============================================================================
# commands.proto.nix
#
# Protobuf schema for workspace commands configuration.
# Defines reusable commands for the development environment.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "commands.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  messages = {
    # Individual command configuration
    Command = proto.mkMessage {
      name = "Command";
      description = "A workspace command definition";
      fields = {
        package = proto.string 1 "Package that provides the binary";
        bin = proto.optional (proto.string 2 "Optional binary name if different from tool name");
        args = proto.repeated (proto.string 3 "Arguments to pass to the tool");
        config_path = proto.optional (proto.string 4 "Optional config file path for the tool");
        config_arg = proto.repeated (
          proto.string 5 "Argument prefix inserted before configPath (e.g. --config)"
        );
        env = proto.map "string" "string" 6 "Environment variables for the tool";
        cwd = proto.optional (proto.string 7 "Working directory for the tool");
      };
    };

    # Root commands map
    Commands = proto.mkMessage {
      name = "Commands";
      description = "Primary workspace commands configuration";
      fields = {
        commands = proto.map "string" "Command" 1 "Map of command name to command config";
      };
    };
  };
}
