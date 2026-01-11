# ==============================================================================
# apps.proto.nix
#
# Protobuf schema for application configuration.
# Defines app-level settings for serialization/codegen.
#
# Note: Complex tooling configuration (install, build, test, etc.) is
# Nix-specific and defined in core/options/apps.nix, not here.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "apps.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  enums = {
    AppVariableType = proto.mkEnum {
      name = "AppVariableType";
      description = "Type of environment variable";
      values = [
        "APP_VARIABLE_TYPE_UNSPECIFIED"
        "APP_VARIABLE_TYPE_LITERAL"
        "APP_VARIABLE_TYPE_VARIABLE"
        "APP_VARIABLE_TYPE_VALS"
      ];
    };
  };

  messages = {
    # Environment variables
    AppVariable = proto.mkMessage {
      name = "AppVariable";
      description = "Environment variable configuration";
      fields = {
        key = proto.string 1 "value will be passed to app using this key";
        description = proto.optional (proto.string 2 "(optional) Description of the variable");
        type = proto.message "AppVariableType" 3 "Type of environment variable";
        value = proto.string 4 ''
          - When type = "LITERAL", the value will be passed as is.
          - When type = "VARIABLE", should refer to the key of the variable or secret.
          - When type = "VALS", should contain a [vals](https://github.com/helmfile/vals)
            compatible descriptor, for example if you want to get a value from AWS Parameter
            Store: `ref+awsssm://PATH/TO/PARAM[?region=REGION&role_arn=ASSUMED_ROLE_ARN]
        '';
      };
    };
    # App Tasks, corresponds to npm package scripts
    AppTask = proto.mkMessage {
      name = "AppTask";
      description = "Command configuration";
      fields = {
        key = proto.string 1 "Corresponds to CMD in  `turbo task run CMD`";
        description = proto.optional (proto.string 2 "(optional) Description of the command");
        command = proto.string 3 "Command to run";
        env = proto.map "string" "AppVariable" 4 "Environment variables to set";
      };
    };
    # Individual app configuration (data only, not runtime config)
    # Uses embedded model: tasks/variables are maps where key = ID/name
    App = proto.mkMessage {
      name = "App";
      description = "Configuration for a single application in the workspace";
      fields = {
        name = proto.string 1 "Display name of the app";
        description = proto.optional (proto.string 2 "Description of the app");
        path = proto.string 3 "Relative path to the app directory";
        type = proto.optional (proto.string 4 "App type/runtime (bun, go, python, rust, etc.)");
        port = proto.optional (proto.int32 5 "Development server port");
        domain = proto.optional (proto.string 6 "Local development domain");
        tasks = proto.map "string" "AppTask" 7 "Tasks for this app (key = task name)";
        variables = proto.map "string" "AppVariable" 8 "Environment variables (key = variable name)";
      };
    };

    # Collection of apps keyed by app identifier
    Apps = proto.mkMessage {
      name = "Apps";
      description = "Map of app identifier to app configuration";
      fields = {
        apps = proto.map "string" "App" 1 "Map of app ID to app config";
      };
    };
  };
}
