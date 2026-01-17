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

  boilerplate = ''
    # apps.nix - Application configuration
    # type: sp-app
    # See: https://stackpanel.dev/docs/apps
    {
      # Example app:
      # web = {
      #   name = "Web App";
      #   description = "Frontend web application";
      #   path = "apps/web";
      #   type = "bun";
      #   port = 3000;
      #   domain = "web.local";
      # };
      #
      # api = {
      #   name = "API Server";
      #   path = "apps/api";
      #   type = "go";
      #   port = 8080;
      # };
    }
  '';

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
        key = proto.string 1 "Environment variable key";
        type = proto.message "AppVariableType" 2 "Type of environment variable";
        variable_id = proto.string 3 "ID of the variable from variables.nix";
        environments = proto.map "string" "AppEnvironment" 4 "Environments this mapping applies to";
        value = proto.optional (proto.string 5 "Literal value (used when variable_id is empty)");
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
    AppEnvironment = proto.mkMessage {
      name = "AppEnvironment";
      description = "Environment configuration (e.g., dev, staging, production)";
      fields = {
        name = proto.string 1 "Name of the environment";
        description = proto.optional (proto.string 2 "(optional) Description of the environment");
        variables = proto.map "string" "AppVariable" 3 "Environment variables (key = env var key)";
        # Secrets-related fields for SOPS/agenix integration
        sources = proto.repeated (
          proto.string 4 ''
            List of SOPS-encrypted source files for this environment (without .yaml extension).
            These files are decrypted and merged to provide secrets for the environment.
            Example: ["shared", "dev"] merges shared.yaml + dev.yaml
          ''
        );
        public-keys = proto.repeated (
          proto.string 5 ''
            List of AGE/SSH public keys that can decrypt secrets for this environment.
            These keys are used when encrypting new secrets.
          ''
        );
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
        variables = proto.map "string" "AppVariable" 8 "Environment variables (key = env var key)";
        environments = proto.map "string" "AppEnvironment" 9 "Environments associated with this app";
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
