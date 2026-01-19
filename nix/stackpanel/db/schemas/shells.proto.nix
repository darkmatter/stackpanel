# ==============================================================================
# shells.proto.nix
#
# Protobuf schema for shell configuration.
# Defines shell-specific settings and configurations.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "shells.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = {
    ShellType = proto.mkEnum {
      name = "ShellType";
      description = "Supported shell types";
      values = [
        "SHELL_TYPE_UNSPECIFIED"
        "SHELL_TYPE_BASH"
        "SHELL_TYPE_ZSH"
        "SHELL_TYPE_FISH"
        "SHELL_TYPE_NUSHELL"
      ];
    };
  };

  messages = {
    # Root shells configuration
    Shells = proto.mkMessage {
      name = "Shells";
      description = "Shell-specific settings and configurations";
      fields = {
        default_shell = proto.message "ShellType" 1 "Default shell type";
        common = proto.message "Profile" 2 "Common settings applied to all shells";
        bash = proto.message "Profile" 3 "Bash-specific settings";
        zsh = proto.message "Profile" 4 "Zsh-specific settings";
        fish = proto.message "Profile" 5 "Fish-specific settings";
        hooks = proto.repeated (proto.message "Hook" 6 "Shell hooks to run on initialization");
        path_prepend = proto.repeated (proto.string 7 "Directories to prepend to PATH");
        path_append = proto.repeated (proto.string 8 "Directories to append to PATH");
      };
    };

    # Shell profile configuration
    Profile = proto.mkMessage {
      name = "Profile";
      description = "Shell profile configuration";
      fields = {
        env = proto.map "string" "EnvVar" 1 "Environment variables";
        aliases = proto.map "string" "Alias" 2 "Shell aliases";
        init_extra = proto.optional (proto.string 3 "Extra shell initialization script");
        history_size = proto.int32 4 "Number of history entries to keep";
        history_ignore = proto.repeated (proto.string 5 "Patterns to ignore in history");
      };
    };

    # Environment variable configuration
    EnvVar = proto.mkMessage {
      name = "EnvVar";
      description = "Environment variable configuration";
      fields = {
        value = proto.string 1 "Environment variable value";
        secret = proto.bool 2 "Whether this value should be treated as a secret";
        description = proto.optional (proto.string 3 "Description of what this variable is for");
      };
    };

    # Shell alias configuration
    Alias = proto.mkMessage {
      name = "Alias";
      description = "Shell alias configuration";
      fields = {
        command = proto.string 1 "Command to alias to";
        description = proto.optional (proto.string 2 "Description of the alias");
      };
    };

    # Shell hook configuration
    Hook = proto.mkMessage {
      name = "Hook";
      description = "Shell hook configuration";
      fields = {
        name = proto.string 1 "Hook name/identifier";
        script = proto.string 2 "Shell script to execute";
        order = proto.int32 3 "Execution order (lower runs first)";
        enabled = proto.bool 4 "Whether this hook is enabled";
      };
    };
  };
}
