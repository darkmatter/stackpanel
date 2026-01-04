# ==============================================================================
# nix/stackpanel/db/lib/types.nix
#
# Nix-first schema definitions that generate JSON Schema for codegen.
#
# Philosophy: Write schemas using familiar mkOption-style syntax.
# The library converts Nix types to JSON Schema for TypeScript/Go generation.
#
# Usage:
#   mkSchemaOption {
#     type = types.str;
#     description = "User's display name";
#   }
#
# The above generates both the Nix option AND the equivalent JSON Schema.
# ==============================================================================
{ lib }:
let
  types = lib.types;

  # =============================================================================
  # Nix Type -> JSON Schema Mapping
  # =============================================================================

  # Get the internal type name from a Nix type
  # This handles the various ways Nix types expose their name
  getTypeName =
    type:
    type.name or (
      if type ? functor.name then
        type.functor.name
      else if type ? description then
        # Parse from description like "list of strings"
        let
          desc = type.description;
        in
        if lib.hasPrefix "list of " desc then
          "listOf"
        else if lib.hasPrefix "attribute set of " desc then
          "attrsOf"
        else if lib.hasPrefix "null or " desc then
          "nullOr"
        else if desc == "string" then
          "str"
        else if desc == "signed integer" then
          "int"
        else if desc == "boolean" then
          "bool"
        else
          "unknown"
      else
        "unknown"
    );

  # Extract the nested type from compound types (listOf, attrsOf, nullOr)
  # For listOf/attrsOf, it's in nestedTypes.elemType
  # For nullOr, it's in functor.payload
  getNestedType =
    type:
    if type ? nestedTypes.elemType then
      type.nestedTypes.elemType
    else if
      type ? functor.payload && builtins.isAttrs type.functor.payload && type.functor.payload ? name
    then
      # functor.payload is itself a type
      type.functor.payload
    else
      null;

  # Convert a Nix lib.types.* to JSON Schema
  nixTypeToJsonSchema =
    type:
    let
      typeName = getTypeName type;
      nestedType = getNestedType type;
    in
    {
      # Basic types
      "str" = {
        type = "string";
      };
      "string" = {
        type = "string";
      };
      "int" = {
        type = "integer";
      };
      "ints" = {
        type = "integer";
      };
      "signedInt" = {
        type = "integer";
      };
      "number" = {
        type = "number";
      };
      "float" = {
        type = "number";
      };
      "bool" = {
        type = "boolean";
      };
      "boolean" = {
        type = "boolean";
      };
      "path" = {
        type = "string";
        format = "path";
      };
      "anything" = { };
      "unspecified" = { };
      "attrs" = {
        type = "object";
      };
      "raw" = { };

      # Compound types
      "listOf" =
        let
          itemSchema = if nestedType != null then nixTypeToJsonSchema nestedType else { };
        in
        {
          type = "array";
          items = itemSchema;
        };

      "nonEmptyListOf" =
        let
          itemSchema = if nestedType != null then nixTypeToJsonSchema nestedType else { };
        in
        {
          type = "array";
          items = itemSchema;
          minItems = 1;
        };

      "attrsOf" =
        let
          valueSchema = if nestedType != null then nixTypeToJsonSchema nestedType else { };
        in
        {
          type = "object";
          additionalProperties = valueSchema;
        };

      "nullOr" =
        let
          innerSchema = if nestedType != null then nixTypeToJsonSchema nestedType else { };
        in
        innerSchema
        // {
          type = [
            (innerSchema.type or "string")
            "null"
          ];
        };

      # Submodule - requires special handling with options
      "submodule" = {
        type = "object";
      };

      # Enum types - payload is { values = [...] }
      "enum" =
        let
          payload = type.functor.payload or { };
          values = if builtins.isList payload then payload else payload.values or [ ];
        in
        if builtins.all builtins.isString values then
          {
            type = "string";
            enum = values;
          }
        else
          { enum = values; };

      # oneOf/either
      "either" = { }; # Would need anyOf handling
      "oneOf" = { }; # Would need anyOf handling

    }
    .${typeName} or { };

  # =============================================================================
  # Schema Option Builder (mkOption-style)
  # =============================================================================

  # Create a schema option with metadata for both Nix options and JSON Schema
  # This is the primary API - feels like mkOption but generates JSON Schema too
  mkSchemaOption =
    {
      type, # lib.types.* (e.g., types.str, types.listOf types.str)
      description ? "", # Used in both Nix option and JSON Schema
      default ? null, # Default value
      example ? null, # Example value
      nullable ? false, # Whether the value can be null
      enum ? null, # Enum values (overrides type for JSON Schema)
      format ? null, # JSON Schema format hint (e.g., "email", "uri")
      pattern ? null, # JSON Schema regex pattern for strings
      minimum ? null, # JSON Schema minimum for numbers
      maximum ? null, # JSON Schema maximum for numbers
      minItems ? null, # JSON Schema minItems for arrays
      maxItems ? null, # JSON Schema maxItems for arrays
      required ? true, # Whether this field is required in the parent schema
      additionalProperties ? null, # For object types: schema for additional properties (JSON Schema or mkSchemaOption result)
      ...
    }@args:
    let
      # Determine the effective type (handle nullable)
      effectiveType = if nullable then types.nullOr type else type;

      # Build the JSON Schema
      baseJsonSchema = nixTypeToJsonSchema type;
      jsonSchemaWithDesc =
        baseJsonSchema // (lib.optionalAttrs (description != "") { inherit description; });
      jsonSchemaWithDefault =
        jsonSchemaWithDesc // (lib.optionalAttrs (default != null) { inherit default; });
      jsonSchemaWithEnum =
        jsonSchemaWithDefault
        // (lib.optionalAttrs (enum != null) {
          inherit enum;
          type = "string";
        });
      jsonSchemaWithFormat =
        jsonSchemaWithEnum // (lib.optionalAttrs (format != null) { inherit format; });
      jsonSchemaWithPattern =
        jsonSchemaWithFormat // (lib.optionalAttrs (pattern != null) { inherit pattern; });
      jsonSchemaWithMin =
        jsonSchemaWithPattern // (lib.optionalAttrs (minimum != null) { inherit minimum; });
      jsonSchemaWithMax = jsonSchemaWithMin // (lib.optionalAttrs (maximum != null) { inherit maximum; });
      jsonSchemaWithMinItems =
        jsonSchemaWithMax // (lib.optionalAttrs (minItems != null) { inherit minItems; });
      jsonSchemaWithMaxItems =
        jsonSchemaWithMinItems // (lib.optionalAttrs (maxItems != null) { inherit maxItems; });
      jsonSchemaWithNullable =
        jsonSchemaWithMaxItems
        // (lib.optionalAttrs nullable {
          type = [
            (jsonSchemaWithMaxItems.type or "string")
            "null"
          ];
        });
      # Handle additionalProperties for object types (attrsOf)
      jsonSchemaWithAdditionalProps =
        jsonSchemaWithNullable
        // (lib.optionalAttrs (additionalProperties != null) {
          additionalProperties =
            # If it's a mkSchemaOption/buildSubmoduleSchema result, extract jsonSchema
            if additionalProperties ? jsonSchema then
              additionalProperties.jsonSchema
            # Otherwise assume it's already a JSON Schema
            else
              additionalProperties;
        });
      jsonSchema = jsonSchemaWithAdditionalProps;

      # Build the Nix option
      nixOption = lib.mkOption (
        {
          type = effectiveType;
        }
        // lib.optionalAttrs (description != "") { inherit description; }
        // lib.optionalAttrs (default != null) { inherit default; }
        // lib.optionalAttrs (example != null) { inherit example; }
      );

    in
    {
      # The Nix mkOption result
      option = nixOption;

      # The JSON Schema for this field
      jsonSchema = jsonSchema;

      # The Nix type (for direct use)
      nixType = effectiveType;

      # Whether this field is required
      inherit required;

      # Pass-through for building submodules
      inherit
        type
        description
        default
        example
        ;
    };

  # =============================================================================
  # Schema Builder (for complete schemas)
  # =============================================================================

  # Build a complete schema from mkSchemaOption fields
  # Returns both a Nix submodule type AND a JSON Schema
  mkSchema =
    {
      name, # Schema name (e.g., "User", "Users")
      description ? "", # Schema description
      filename ? null, # Output filename for scaffolding
      boilerplate ? "", # Boilerplate content for scaffolded files
      options ? { }, # Attribute set of mkSchemaOption results
      additionalProperties ? null, # For map/dict types: the value schema
      isMap ? false, # If true, this is a map type (attrsOf)
    }:
    let
      # Convert options to JSON Schema properties
      jsonSchemaProperties = lib.mapAttrs (
        name: opt:
        if opt ? jsonSchema then opt.jsonSchema else nixTypeToJsonSchema (opt.type or types.anything)
      ) options;

      # Get required fields
      requiredFields = lib.filter (
        name:
        let
          opt = options.${name};
        in
        (opt.required or true) && (opt.default or null) == null
      ) (builtins.attrNames options);

      # Build the JSON Schema
      jsonSchemaForObject = {
        type = "object";
        properties = jsonSchemaProperties;
      }
      // lib.optionalAttrs (description != "") { inherit description; }
      // lib.optionalAttrs (requiredFields != [ ]) { required = requiredFields; };

      # For map types (attrsOf), use additionalProperties
      jsonSchemaForMap = {
        type = "object";
      }
      // lib.optionalAttrs (description != "") { inherit description; }
      // lib.optionalAttrs (additionalProperties != null) {
        additionalProperties =
          if additionalProperties ? jsonSchema then
            additionalProperties.jsonSchema
          else if builtins.isAttrs additionalProperties then
            additionalProperties
          else
            { };
      };

      jsonSchema = if isMap then jsonSchemaForMap else jsonSchemaForObject;

      # Build the Nix type
      nixOptionsForSubmodule = lib.mapAttrs (
        name: opt: if opt ? option then opt.option else lib.mkOption { type = opt.type or types.anything; }
      ) options;

      nixTypeForObject = types.submodule { options = nixOptionsForSubmodule; };

      nixTypeForMap =
        if additionalProperties != null then
          types.attrsOf (
            if additionalProperties ? nixType then
              additionalProperties.nixType
            else if additionalProperties ? option then
              additionalProperties.option.type
            else
              types.anything
          )
        else
          types.attrsOf types.anything;

      nixType = if isMap then nixTypeForMap else nixTypeForObject;

    in
    {
      inherit
        name
        description
        filename
        boilerplate
        nixType
        ;

      # Full JSON Schema with $schema and title
      schema = {
        "$schema" = "http://json-schema.org/draft-07/schema#";
        title = name;
      }
      // jsonSchema;

      # Raw JSON Schema (without $schema wrapper)
      jsonSchema = jsonSchema;

      # The options (for reference/extension)
      inherit options;

      # Helper to create an mkOption with this schema's type
      mkOption =
        args:
        lib.mkOption (
          {
            type = nixType;
            inherit description;
          }
          // args
        );

      # Type name for codegen
      typeName = name;
    };

  # =============================================================================
  # Convenience Builders (mkOption-style shortcuts)
  # =============================================================================

  # String field
  str =
    description:
    mkSchemaOption {
      type = types.str;
      inherit description;
    };

  strWithDefault =
    description: default:
    mkSchemaOption {
      type = types.str;
      inherit description default;
      required = false;
    };

  nullableStr =
    description:
    mkSchemaOption {
      type = types.str;
      inherit description;
      nullable = true;
      required = false;
    };

  # Integer field
  int =
    description:
    mkSchemaOption {
      type = types.int;
      inherit description;
    };

  intWithDefault =
    description: default:
    mkSchemaOption {
      type = types.int;
      inherit description default;
      required = false;
    };

  # Number field
  number =
    description:
    mkSchemaOption {
      type = types.number;
      inherit description;
    };

  # Boolean field
  bool =
    description:
    mkSchemaOption {
      type = types.bool;
      inherit description;
    };

  boolWithDefault =
    description: default:
    mkSchemaOption {
      type = types.bool;
      inherit description default;
      required = false;
    };

  # List of strings
  listOfStr =
    description:
    mkSchemaOption {
      type = types.listOf types.str;
      inherit description;
      default = [ ];
      required = false;
    };

  # Enum field
  enum =
    description: values:
    mkSchemaOption {
      type = types.enum values;
      inherit description;
      enum = values;
    };

  enumWithDefault =
    description: values: default:
    mkSchemaOption {
      type = types.enum values;
      inherit description default;
      enum = values;
      required = false;
    };

  # Submodule (nested object with defined fields)
  submodule =
    description: options:
    mkSchemaOption {
      type = types.submodule { inherit options; };
      inherit description;
    };

  # Map/dict type (attrsOf)
  attrsOf =
    description: valueSchema:
    mkSchemaOption {
      type = types.attrsOf (valueSchema.nixType or types.anything);
      inherit description;
      additionalProperties =
        valueSchema.jsonSchema or (nixTypeToJsonSchema (valueSchema.nixType or types.anything));
    };

  # Build a submodule schema from options (for nested objects)
  # Usage: buildSubmoduleSchema "Description" { options... }
  buildSubmoduleSchema =
    description: optionsSet:
    let
      schemaResult = mkSchema {
        name = "Submodule";
        inherit description;
        options = optionsSet;
      };
    in
    mkSchemaOption {
      type = schemaResult.nixType;
      inherit description;
      additionalProperties = null;
    }
    // {
      jsonSchema = schemaResult.jsonSchema;
    };

  # Build a submodule schema with a specific type name (for codegen)
  # Usage: buildNamedSubmoduleSchema "TypeName" "Description" { options... }
  #
  # Use this when you need a unique type name to avoid collisions in generated
  # code (e.g., "OnboardingStep" instead of generic "Step")
  buildNamedSubmoduleSchema =
    name: description: optionsSet:
    let
      schemaResult = mkSchema {
        inherit name description;
        options = optionsSet;
      };
    in
    mkSchemaOption {
      type = schemaResult.nixType;
      inherit description;
      additionalProperties = null;
    }
    // {
      # Include title in jsonSchema so quicktype uses our name
      jsonSchema = schemaResult.jsonSchema // {
        title = name;
      };
    };

in
{
  # Core API
  inherit mkSchemaOption mkSchema nixTypeToJsonSchema;

  # Convenience builders (mkOption-style)
  inherit
    str
    strWithDefault
    nullableStr
    int
    intWithDefault
    number
    bool
    boolWithDefault
    listOfStr
    enum
    enumWithDefault
    submodule
    attrsOf
    buildSubmoduleSchema
    buildNamedSubmoduleSchema
    ;

  # Re-export types for convenience
  types = types;
}
