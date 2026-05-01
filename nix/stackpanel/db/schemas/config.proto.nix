# ==============================================================================
# config.proto.nix
#
# Protobuf schema for Stackpanel project configuration.
# This is the root configuration file at .stackpanel/config.nix
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "config.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    # Root configuration message
    Config = proto.mkMessage {
      name = "Config";
      description = "Stackpanel project configuration";
      fields = {
        enable = proto.withExample true (proto.bool 1 "Enable stackpanel for this project");
        name = proto.withExample "stackpanel-demo" (proto.string 2 "Project name");
        github = proto.withExample "darkmatter/stackpanel" (proto.string 3 "GitHub repository (owner/repo format)");
        debug = proto.withExample false (proto.bool 4 "Enable debug output");
      };
    };
  };
}
