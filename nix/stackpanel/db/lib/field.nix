# ==============================================================================
# nix/stackpanel/db/lib/field.nix
#
# Unified field definition system for Stackpanel.
#
# A single `mkSpField` call produces a value that simultaneously serves as:
#   1. A proto field definition (for .proto codegen → Go/TS typed structs)
#   2. A Nix option source (via `asOption` → lib.mkOption)
#   3. A UI panel field source (via `ui` metadata → panel auto-generation)
#
# This replaces the pattern of defining proto fields, Nix options, and panel
# fields in three separate places. The person defining the field controls
# how it renders in the UI at definition time.
#
# Usage:
#   let sp = import ./field.nix { inherit lib; };
#   in {
#     fields = {
#       mainPackage = sp.string {
#         index = 1;
#         description = "Go main package path";
#         default = ".";
#         ui = { label = "Main Package"; };
#       };
#
#       binaryName = sp.string {
#         index = 2;
#         description = "Binary name";
#         optional = true;
#         ui = { label = "Binary Name"; };
#       };
#
#       # Hidden from UI panels
#       tools = sp.string {
#         index = 3;
#         repeated = true;
#         description = "Go tool dependencies";
#         ui = null;
#       };
#     };
#   }
#
# Converting to Nix options:
#   options.go = lib.types.submodule {
#     options.mainPackage = sp.asOption fields.mainPackage;
#   };
#
# Casing convention:
#   - Field attrset keys: camelCase (mainPackage, binaryName)
#   - Proto output: snake_case (main_package, binary_name) via camelToSnake
#   - Nix options: camelCase (zero conversion)
#   - JSON/Go/TS: camelCase (zero conversion)
#   - editPath: camelCase (zero conversion)
# ==============================================================================
{ lib }:
let
  proto = import ./proto.nix { inherit lib; };
  optionsLib = import ./options.nix { inherit lib; };

  # ===========================================================================
  # String utilities
  # ===========================================================================

  # Convert camelCase to snake_case for proto field rendering
  # "mainPackage" → "main_package"
  # "binaryName" → "binary_name"
  # "version" → "version" (no change)
  camelToSnake =
    str:
    let
      chars = lib.stringToCharacters str;
      upperChars = lib.stringToCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
      isUpper = c: builtins.elem c upperChars;
      processChar =
        i: c:
        if i == 0 then
          lib.toLower c
        else if isUpper c then
          "_${lib.toLower c}"
        else
          c;
    in
    lib.concatStrings (lib.imap0 processChar chars);

  # ===========================================================================
  # UI type constants
  # ===========================================================================

  # Panel field types that map to frontend form controls
  uiType = {
    text = "FIELD_TYPE_STRING";
    number = "FIELD_TYPE_NUMBER";
    toggle = "FIELD_TYPE_BOOLEAN";
    select = "FIELD_TYPE_SELECT";
    multiselect = "FIELD_TYPE_MULTISELECT";
    json = "FIELD_TYPE_JSON";
    code = "FIELD_TYPE_CODE";
  };

  # Infer a UI type from a proto scalar type
  inferUiType =
    type:
    {
      "string" = uiType.text;
      "int32" = uiType.number;
      "int64" = uiType.number;
      "uint32" = uiType.number;
      "uint64" = uiType.number;
      "bool" = uiType.toggle;
      "double" = uiType.number;
      "float" = uiType.number;
    }
    .${type} or uiType.text;

  # Infer UI type considering field modifiers (repeated, map, etc.)
  inferUiTypeForField =
    field:
    if field.mapKey != null then
      uiType.json
    else if field.repeated then
      if field.type == "string" then uiType.multiselect else uiType.json
    else
      inferUiType field.type;

  # ===========================================================================
  # Core field builder
  # ===========================================================================

  # Create a unified field definition.
  # Extends proto.mkField with Nix defaults and UI metadata.
  #
  # Arguments:
  #   type        - Proto scalar type: "string", "int32", "bool", etc.
  #   index       - Proto field number (required, used for codegen)
  #   description - Human-readable description (used for proto comments, Nix docs, UI labels)
  #   default     - Nix default value (overrides proto-inferred default)
  #   example     - Example value (for docs and UI placeholder)
  #   optional    - Proto optional modifier (maps to nullOr in Nix)
  #   repeated    - Proto repeated modifier (maps to listOf in Nix)
  #   mapKey      - Proto map key type (maps to attrsOf in Nix)
  #   ui          - UI rendering metadata, or null to hide from panels
  #
  mkSpField =
    {
      type,
      index,
      description ? "",
      default ? null,
      example ? null,
      optional ? false,
      repeated ? false,
      mapKey ? null,
      ui ? { },
    }:
    let
      # Build the underlying proto field
      protoField = proto.mkField {
        inherit
          type
          optional
          repeated
          mapKey
          example
          ;
        number = index;
        inherit description;
      };

      # Resolve UI metadata
      # {} = auto-infer everything from field type
      # null = hidden from panels entirely
      # { type = ...; label = ...; } = explicit overrides
      resolvedUi =
        if ui == null then
          null
        else
          {
            type = ui.type or (inferUiTypeForField protoField);
            label = ui.label or description;
            editable = ui.editable or true;
            order = ui.order or (index * 10);
            placeholder = ui.placeholder or null;
            options = ui.options or [ ];
            hidden = ui.hidden or false;
            # Help text: use UI-specific description override, or fall back to field description
            description = ui.description or description;
            # Example value for additional context
            example = ui.example or example;
          };
    in
    protoField
    // {
      _isSpField = true;
      inherit default;
      ui = resolvedUi;
    };

  # ===========================================================================
  # Convenience constructors
  # ===========================================================================

  # Each mirrors proto.nix's constructors but takes an attrset for clarity.
  # All require `index` (proto field number).

  string = args: mkSpField ({ type = "string"; } // args);
  int32 = args: mkSpField ({ type = "int32"; } // args);
  int64 = args: mkSpField ({ type = "int64"; } // args);
  uint32 = args: mkSpField ({ type = "uint32"; } // args);
  uint64 = args: mkSpField ({ type = "uint64"; } // args);
  bool = args: mkSpField ({ type = "bool"; } // args);
  double = args: mkSpField ({ type = "double"; } // args);
  float = args: mkSpField ({ type = "float"; } // args);

  # ===========================================================================
  # Option conversion
  # ===========================================================================

  # Convert an SpField to a Nix module option (lib.mkOption).
  #
  # Usage:
  #   options.mainPackage = sp.asOption fields.mainPackage;
  #
  # The resulting option has the correct Nix type, default, and description
  # derived from the field definition. No metadata is attached to the option
  # itself - UI metadata stays on the field definition and is accessed by the
  # panel generator via direct import.
  #
  asOption =
    field:
    assert
      field._isSpField or false
      || throw "asOption: expected an SpField (created by mkSpField), got: ${builtins.toJSON field}";
    let
      nixType = optionsLib.protoTypeToNix { inherit field; };
      protoDefault = optionsLib.getFieldDefault { inherit field; };
      finalDefault = if field.default != null then field.default else protoDefault;
    in
    lib.mkOption (
      {
        type = nixType;
        description = field.description;
        default = finalDefault;
      }
      // lib.optionalAttrs (field.example != null) {
        example = field.example;
      }
    );

  # ===========================================================================
  # Proto message helpers
  # ===========================================================================

  # Convert camelCase field keys to snake_case for proto message rendering.
  #
  # Usage:
  #   message = proto.mkMessage {
  #     name = "GoAppConfig";
  #     fields = sp.toProtoFields fields;
  #   };
  #
  toProtoFields =
    fields: lib.mapAttrs' (name: value: lib.nameValuePair (camelToSnake name) value) fields;

  # ===========================================================================
  # UI metadata extraction
  # ===========================================================================

  # Check if a field should be visible in panels
  isUiVisible = field: (field._isSpField or false) && field.ui != null && !(field.ui.hidden or false);

  # Filter fields to only those visible in UI
  uiVisibleFields = fields: lib.filterAttrs (_name: isUiVisible) fields;

  # Extract the UI metadata from a field for panel serialization
  fieldToUiMeta = name: field: {
    inherit name;
    type = field.ui.type;
    label = field.ui.label;
    editable = field.ui.editable;
    order = field.ui.order;
    placeholder = field.ui.placeholder;
    options = field.ui.options;
  };

in
{
  # Core builder
  inherit mkSpField;

  # Convenience constructors
  inherit
    string
    int32
    int64
    uint32
    uint64
    bool
    double
    float
    ;

  # Nix option conversion
  inherit asOption;

  # Proto helpers
  inherit toProtoFields camelToSnake;

  # UI metadata
  inherit
    uiType
    inferUiType
    isUiVisible
    uiVisibleFields
    fieldToUiMeta
    ;
}
