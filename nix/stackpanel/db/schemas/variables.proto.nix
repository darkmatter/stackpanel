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
    # VariableType indicates how the variable value is resolved
    VariableType = proto.mkEnum {
      name = "VariableType";
      values = [
        "LITERAL"   # Plain text value, embedded directly (resolved at eval time)
        "SECRET"    # Encrypted with AGE master keys (resolved at runtime)
        "VALS"      # External value reference using vals syntax (resolved at runtime)
        "EXEC"      # Shell command that outputs the value (resolved at runtime)
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
          Globally unique identifier for the variable. Recommended format:
          `/path/based/variable-name` for organization (e.g., `/prod/postgres-url`).
        '';
        key = proto.string 2 ''
          Environment variable name when passing to apps (e.g., POSTGRES_URL).
        '';
        description = proto.optional (proto.string 3 "Description of the variable");
        type = proto.message "VariableType" 4 "How the variable value is resolved";
        value = proto.string 5 ''
          The value field meaning depends on type:
          - LITERAL: The actual value (embedded directly)
          - SECRET: Empty (value lives in encrypted .age file)
          - VALS: A vals-compatible reference (e.g., ref+awsssm://path/to/param)
          - EXEC: Shell command to execute (stdout becomes the value)
        '';
        masterKeys = proto.repeated (
          proto.string 6 ''
            Master keys that can decrypt this secret. Only used when type=SECRET.
            The .age file is encrypted to ALL listed master keys.
            Default: ["local"] (auto-generated local key).
            Example: ["dev", "prod"] for team-accessible secrets.
          ''
        );
        # Module dependency tracking
        requiredBy = proto.repeated (
          proto.string 7 ''
            List of module names that require this variable (e.g., ["sst", "ci"]).
          ''
        );
        providedBy = proto.optional (
          proto.string 8 ''
            Module name that provides/creates this variable.
          ''
        );
        level = proto.optional (
          proto.int32 9 ''
            Bootstrap level (0 = always available, 1+ = requires dependencies).
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
