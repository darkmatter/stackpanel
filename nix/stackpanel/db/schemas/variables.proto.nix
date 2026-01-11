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
        key = proto.string 1 "value will be passed to app using this key";
        description = proto.optional (proto.string 2 "(optional) Description of the variable");
        type = proto.message "VariableType" 3 "Type of the variable";
        value = proto.string 4 ''
          - When type = "VARIABLE", the value wil be provided as-is.
          - When type = "SECRET", should refer to the key of the secret.
          - When type = "VALS", should contain a [vals](https://github.com/helmfile/vals)
            compatible descriptor, for example if you want to get a value from AWS Parameter
            Store: `ref+awsssm://PATH/TO/PARAM[?region=REGION&role_arn=ASSUMED_ROLE_ARN]`
        '';
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
