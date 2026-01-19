# ==============================================================================
# onboarding.proto.nix
#
# Protobuf schema for onboarding configuration.
# Defines onboarding steps and configuration for new team members.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "onboarding.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = {
    StepType = proto.mkEnum {
      name = "StepType";
      description = "Type of onboarding step";
      values = [
        "STEP_TYPE_UNSPECIFIED"
        "STEP_TYPE_COMMAND"
        "STEP_TYPE_MANUAL"
        "STEP_TYPE_CHECK"
        "STEP_TYPE_LINK"
        "STEP_TYPE_PROMPT"
      ];
    };
  };

  messages = {
    # Root onboarding configuration
    Onboarding = proto.mkMessage {
      name = "Onboarding";
      description = "Onboarding configuration for new team members";
      fields = {
        enable = proto.bool 1 "Enable onboarding system";
        welcome_message = proto.string 2 "Welcome message shown to new team members";
        completion_message = proto.string 3 "Message shown when onboarding is complete";
        categories = proto.map "string" "Category" 4 "Categories for organizing onboarding steps";
        steps = proto.map "string" "Step" 5 "Onboarding steps";
        auto_run = proto.bool 6 "Automatically run onboarding on first shell entry";
        persist_state = proto.bool 7 "Persist completed steps across shell sessions";
        state_file = proto.string 8 "Path to store onboarding state";
      };
    };

    # Onboarding category configuration
    Category = proto.mkMessage {
      name = "Category";
      description = "Onboarding category configuration";
      fields = {
        title = proto.string 1 "Display title for the category";
        description = proto.optional (proto.string 2 "Description of what this category covers");
        order = proto.int32 3 "Order in which this category appears";
        icon = proto.optional (proto.string 4 "Icon for the category (emoji or Nerd Font icon)");
      };
    };

    # Onboarding step configuration
    Step = proto.mkMessage {
      name = "Step";
      description = "Onboarding step configuration";
      fields = {
        id = proto.string 1 "Unique identifier for this step";
        title = proto.string 2 "Display title for the step";
        description = proto.optional (proto.string 3 "Detailed description of what this step accomplishes");
        type = proto.message "StepType" 4 "Type of onboarding step";
        command = proto.optional (proto.string 5 "Command to run (for 'command' type steps)");
        check_command = proto.optional (
          proto.string 6 "Command to verify step completion (exit 0 = complete)"
        );
        url = proto.optional (proto.string 7 "URL to open (for 'link' type steps)");
        required = proto.bool 8 "Whether this step is required";
        order = proto.int32 9 "Order in which this step should be presented";
        category = proto.string 10 "Category/group for organizing steps";
        depends_on = proto.repeated (
          proto.string 11 "List of step IDs that must be completed before this step"
        );
        env = proto.repeated (proto.string 12 "Environments where this step applies");
        skip_if = proto.optional (proto.string 13 "Condition command - skip step if exits 0");
      };
    };
  };
}
