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
  name = "variables.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  enums = {
    VariableType = proto.mkEnum {
      name = "VariableType";
      values = [
        "VARIABLE"
        "SECRET"
        "VALS"
      ];
    };
  };

  messages = {
    Variable = proto.mkMessage {
      name = "Variable";
      description = "Configuration for a single variable in the workspace";
      fields = {
        id = proto.string 1 ''
          Globally unique identifier for the variable. You can reference a single
          variable in multiple apps and environments, so to avoid confusion, it's
          recommended to use a format like `my-variable-name` rather than `MY_VARIABLE_NAME`.
          You can also use `/path/based/variable-name` for organization. If a variable should
          only be used in a specific environment or app, you should include that detail in
          this field.
        '';
        key = proto.string 2 ''
          Default key to use when passing the variable to the app. This is the key that will be used
          in the environment variables of the app.
        '';
        description = proto.optional (proto.string 3 "(optional) Description of the variable");
        type = proto.message "VariableType" 4 "Type of the variable";
        value = proto.string 5 ''
          - When type = "VARIABLE", the value wil be provided as-is.
          - When type = "SECRET", then the value will be encrypted with age and store in <secrets-path>/<id>.age.
          - When type = "VALS", should contain a [vals](https://github.com/helmfile/vals)
            compatible descriptor, for example if you want to get a value from AWS Parameter
            Store: `ref+awsssm://PATH/TO/PARAM[?region=REGION&role_arn=ASSUMED_ROLE_ARN]`
        '';
        environments = proto.repeated (
          proto.string 6 ''
            List of environments this variable/secret is available in.
            If empty, the variable is available in all environments.
            Used for access control with secrets - only users with access to
            these environments can decrypt the secret.
          ''
        );
      };
    };

    # Collection of variables keyed by variable identifier
    Variables = proto.mkMessage {
      name = "Variables";
      description = "Map of variable identifier to variable configuration";
      fields = {
        variables = proto.map "string" "Variable" 1 "Map of variable ID to variable config";
      };
    };
  };
}
