# Shared by the module registry and public SDK. Actions take a JSON object on
# stdin; `script` is a single executable, never a shell command template.
{ lib }:
let
  inherit (lib) types mkOption;
  optionalText =
    description:
    mkOption {
      inherit description;
      type = types.nullOr types.str;
      default = null;
    };
in
types.submodule (
  { name, ... }: {
    options = {
      label = mkOption {
        type = types.nonEmptyStr;
        default = name;
        description = "Human-readable action label.";
      };
      description = optionalText "What the action does.";
      icon = optionalText "Lucide icon for this action.";
      script = mkOption {
        type = types.nonEmptyStr;
        description = "Executable name in the project profile or absolute Nix store executable.";
      };
      argsSchema = mkOption {
        type = types.addCheck (types.attrsOf types.anything) (schema: (schema.type or null) == "object");
        default = {
          type = "object";
          properties = { };
          additionalProperties = false;
        };
        description = "JSON Schema object describing the action's input object.";
      };
      confirm = optionalText "Optional confirmation message shown before execution.";
      outputMode = mkOption {
        type = types.enum [
          "stream"
          "json"
        ];
        default = "stream";
        description = "Stream command output or return one JSON document.";
      };
      invalidates = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Entity collections to refresh after successful execution.";
      };
    };
  }
)
