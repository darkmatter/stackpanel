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
    AppEnvironment = proto.mkEnum {
      name = "AppEnvironment";
      description = "Environments an app can be associated with";
      values = [
        "APP_ENVIRONMENT_UNSPECIFIED"
        "APP_ENVIRONMENT_DEV"
        "APP_ENVIRONMENT_STAGING"
        "APP_ENVIRONMENT_PRODUCTION"
      ];
    };
  };

  messages = {
    # Individual app configuration (data only, not runtime config)
    App = proto.mkMessage {
      name = "App";
      description = "Configuration for a single application in the workspace";
      fields = {
        name = proto.string 1 "Display name of the app";
        path = proto.string 2 "Relative path to the app directory";
        install_command = proto.optional (
          proto.string 3 "Custom install command (overrides default behavior)"
        );
        build_command = proto.optional (proto.string 4 "Custom build command (overrides default behavior)");
        format_command = proto.optional (proto.string 5 "Custom code formatting command");
        lint_command = proto.optional (proto.string 6 "Custom linting command");
        test_command = proto.optional (proto.string 7 "Custom test command");
        start_command = proto.optional (proto.string 8 "Custom start/development command");
        environments = proto.repeated (
          proto.message "AppEnvironment" 9 "Environments associated with this app"
        );
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
