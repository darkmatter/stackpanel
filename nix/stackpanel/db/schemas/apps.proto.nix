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
        extends = proto.repeated (
          proto.string 4 "Inherit these environments - useful for sharing environment variables between environments."
        );
        secrets = proto.repeated (
          proto.string 5 ''
            Env var names in this environment that contain sensitive values.
            Used to auto-derive deployment.secrets — these are wrapped with
            alchemy.secret() at deploy time.
          ''
        );
      };
    };

    EnvironmentVariable = proto.mkMessage {
      name = "EnvironmentVariable";
      description = "Environment variable for this app";
      fields = {
        key = proto.string 1 "ID of the environment variable - defaults to key used in the attribute path. KEY will be read from $KEY in the environment";
        required = proto.bool 2 "Whether the environment variable is required";
        secret = proto.bool 3 "Whether the environment variable is sensitive";
        value = proto.optional (proto.string 4 "Value of the environment variable");
        sops = proto.optional (proto.string 5 "Path to the SOPS file for this variable's group");
        defaultValue = proto.optional (proto.string 6 "Default value of the environment variable");
        description = proto.optional (proto.string 7 ''
          Human-readable description of what this variable is for and where to
          obtain it. Surfaced in the studio Variables UI and in the actionable
          error message thrown by `loadAppEnv(..., { validate: true })` when
          the variable is missing.
        '');
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
          deprecated: use env instead
          Environment configurations (key = environment name like "dev", "prod").
        '';
        deploy = proto.message "AppDeploy" 8 "Colmena deployment mapping for this app";
        env = proto.map "string" "EnvironmentVariable" 9 "Environment variables for this app";
        environmentIds = proto.repeated (
          proto.string 10 ''
            Environment IDs for this app. Defaults to "dev", "prod", "staging", "test".
          ''
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
