# ==============================================================================
# tasks.proto.nix
#
# Protobuf schema for task configuration.
# Defines reusable tasks for the development environment.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "tasks.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  messages = {
    Task = proto.mkMessage {
      name = "Task";
      description = "A workspace task definition";
      fields = {
        exec = proto.string 1 "Default task command to execute";
        description = proto.optional (proto.string 2 "Optional description for the task");
        cwd = proto.optional (proto.string 3 "Working directory for the task");
        env = proto.map "string" "string" 4 "Environment variables for the task";
      };
    };

    Tasks = proto.mkMessage {
      name = "Tasks";
      description = "Primary workspace tasks configuration";
      fields = {
        tasks = proto.map "string" "Task" 1 "Map of task name to task config";
      };
    };
  };
}
