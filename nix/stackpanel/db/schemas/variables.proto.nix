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
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = {
    # VariableType indicates how the value is stored/retrieved AND its data type
    # Storage types: VARIABLE (plain), SECRET (age-encrypted), VALS (external)
    # Value types: STRING, NUMBER, BOOLEAN (for codegen)
    VariableType = proto.mkEnum {
      name = "VariableType";
      values = [
        "VARIABLE"  # Plain variable with string value
        "SECRET"    # Age-encrypted secret
        "VALS"      # External value reference (vals syntax)
        "STRING"    # Explicitly typed as string
        "NUMBER"    # Explicitly typed as number (for codegen)
        "BOOLEAN"   # Explicitly typed as boolean (for codegen)
      ];
    };
  };

  messages = {
    # Action to take when a required variable is missing
    VariableAction = proto.mkMessage {
      name = "VariableAction";
      description = "Action to resolve a missing variable";
      fields = {
        type = proto.string 1 ''
          Type of action: "add-secret", "add-variable", "configure", "external"
        '';
        label = proto.optional (proto.string 2 "Button/link label for the action");
        url = proto.optional (proto.string 3 "External URL (e.g., link to create API token)");
        secretKey = proto.optional (proto.string 4 "Secret key name if type=add-secret");
      };
    };

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
        # New fields for module requirements
        requiredBy = proto.repeated (
          proto.string 7 ''
            List of module names that require this variable (e.g., ["sst", "ci"]).
            Used to show which features depend on this variable being set.
          ''
        );
        providedBy = proto.optional (
          proto.string 8 ''
            Module name that provides/creates this variable.
            Used to understand where the variable comes from.
          ''
        );
        level = proto.optional (
          proto.int32 9 ''
            Bootstrap level (0 = always available, 1+ = requires dependencies).
            Level 0: No dependencies (e.g., AGE key, env vars)
            Level 1: Requires level 0 (e.g., encrypted secrets)
            Level 2: Requires external setup (e.g., cloud API tokens)
          ''
        );
        action = proto.optional (
          proto.message "VariableAction" 10 ''
            Action to resolve this variable if missing.
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
