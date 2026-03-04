# ==============================================================================
# apps.proto.nix
#
# Protobuf schema for application configuration.
# Defines app-level settings for serialization/codegen.
#
# Environment variables are simple string maps:
#   ENV_VAR_NAME = "literal-value"
#   ENV_VAR_NAME = "ref+sops://.stack/secrets/dev.yaml#/KEY"
#   ENV_VAR_NAME = "ref+awsssm://path/to/param"
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
    #
    # Commands (dev, build, test, lint, format) are automatically provided
    # based on app type (bun, go, etc.) via Nix-native flake outputs:
    #   nix build .#<app>       - Build for production
    #   nix run .#<app>-dev     - Run dev server
    #   nix flake check         - Run all tests and lints
    {
      # Example bun app:
      # web = {
      #   name = "Web App";
      #   description = "Frontend web application";
      #   path = "apps/web";
      #   type = "bun";
      #   port = 3000;
      #   domain = "web.local";
      #   environments.dev = {
      #     DATABASE_URL = "ref+sops://.stack/secrets/dev.yaml#/DATABASE_URL";
      #     PORT = "3000";
      #   };
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = { };

  messages = {
    # Colmena deployment mapping
    AppDeploy = proto.mkMessage {
      name = "AppDeploy";
      description = "Deployment mapping for Colmena (targets, roles, and modules)";
      fields = {
        enable = proto.bool 1 "Enable deployment mapping for this app";
        targets = proto.repeated (proto.string 2 "Target machine ids or tag selectors");
        role = proto.optional (proto.string 3 "Deployment role label for this app");
        nixos_modules = proto.repeated (proto.string 4 "Extra NixOS modules to import for this app");
        system = proto.optional (proto.string 5 "Target system/architecture (e.g., x86_64-linux)");
        secrets = proto.repeated (proto.string 6 "Secret references required by this app during deploy");
      };
    };

    # Environment configuration
    AppEnvironment = proto.mkMessage {
      name = "AppEnvironment";
      description = "Environment configuration (e.g., dev, staging, production)";
      fields = {
        name = proto.string 1 "Name of the environment";
        description = proto.optional (proto.string 2 "(optional) Description of the environment");
        # Simple map of ENV_VAR_NAME to value (literal or vals reference)
        env = proto.map "string" "string" 3 ''
          Environment variables for this environment.
          Key: Environment variable name (e.g., DATABASE_URL)
          Value: Literal string or vals reference (e.g., ref+sops://...)
        '';
      };
    };

    # Individual app configuration
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
        # Per-environment configuration
        environments = proto.map "string" "AppEnvironment" 7 ''
          Environment configurations (key = environment name like "dev", "prod").
        '';
        deploy = proto.message "AppDeploy" 8 "Colmena deployment mapping for this app";
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
