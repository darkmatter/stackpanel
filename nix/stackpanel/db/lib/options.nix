# ==============================================================================
# nix/stackpanel/db/lib/options.nix
#
# Library for converting Protobuf message definitions to Nix module options.
#
# This module provides utilities to derive Nix `lib.mkOption` definitions from
# proto message schemas, maintaining the proto files as the single source of
# truth for data types.
#
# Usage:
#   let
#     optionsLib = import ./options.nix { inherit lib; };
#   in
#   optionsLib.mkOptionsFromMessage {
#     message = mySchema.messages.User;
#     allMessages = mySchema.messages;
#   }
#
# Exported functions:
#   - snakeToKebab: Convert snake_case to kebab-case
#   - kebabToSnake: Convert kebab-case to snake_case
#   - protoTypeToNix: Map proto field types to Nix types
#   - getFieldDefault: Get default value for a proto field
#   - mkOptionFromField: Build a Nix option from a proto field
#   - mkOptionsFromMessage: Build Nix options attrset from a proto message
#   - mkSubmoduleFromMessage: Build a submodule type from a proto message
#   - mkOptionFromMessage: Build a complete option from a proto message
#   - mkMapOptionFromMessage: Build an attrsOf option for map-style messages
#   - getSchemaMessages: Extract messages from a schema
#   - mkEntityOptions: Build options for an entity (helper for schema registry)
# ==============================================================================
{ lib }:
let
  # ---------------------------------------------------------------------------
  # String case conversion utilities
  # ---------------------------------------------------------------------------
  # Convert snake_case to kebab-case
  # Example: "public_keys" → "public-keys"
  snakeToKebab = str: builtins.replaceStrings [ "_" ] [ "-" ] str;

  # Convert kebab-case to snake_case
  # Example: "public-keys" → "public_keys"
  kebabToSnake = str: builtins.replaceStrings [ "-" ] [ "_" ] str;

  # ---------------------------------------------------------------------------
  # Proto type → Nix type mapping
  # ---------------------------------------------------------------------------

  # Map proto field types to Nix types
  # Handles scalars, message references, maps, repeated fields, and optionals
  protoTypeToNix =
    {
      field,
      allMessages ? { },
    }:
    let
      # Check if it's a message reference (not a scalar type)
      isMessageRef =
        !(builtins.elem field.type [
          "string"
          "int32"
          "int64"
          "uint32"
          "uint64"
          "bool"
          "double"
          "float"
          "bytes"
        ]);

      baseType =
        if isMessageRef then
          # For message references, create a submodule if we have the message definition
          if allMessages ? ${field.type} then
            lib.types.submodule {
              options = mkOptionsFromMessage {
                message = allMessages.${field.type};
                inherit allMessages;
              };
            }
          else
            # Fallback to attrs if message not found
            lib.types.attrs
        else
          # Scalar type mapping
          {
            string = lib.types.str;
            int32 = lib.types.int;
            int64 = lib.types.int;
            uint32 = lib.types.ints.unsigned;
            uint64 = lib.types.ints.unsigned;
            bool = lib.types.bool;
            double = lib.types.float;
            float = lib.types.float;
            bytes = lib.types.str; # Base64 encoded
          }
          .${field.type} or lib.types.str;
    in
    # Apply modifiers based on field properties
    if field.mapKey != null then
      lib.types.attrsOf baseType
    else if field.repeated then
      lib.types.listOf baseType
    else if field.optional then
      lib.types.nullOr baseType
    else
      baseType;

  # ---------------------------------------------------------------------------
  # Default value derivation
  # ---------------------------------------------------------------------------

  # Get default value for a proto field based on its type and modifiers
  getFieldDefault =
    field:
    if field.optional then
      null
    else if field.repeated then
      [ ]
    else if field.mapKey != null then
      { }
    else if field.type == "bool" then
      false
    else if field.type == "string" then
      ""
    else if
      builtins.elem field.type [
        "int32"
        "int64"
        "uint32"
        "uint64"
      ]
    then
      0
    else if
      builtins.elem field.type [
        "float"
        "double"
      ]
    then
      0.0
    else
      { }; # message type defaults to empty attrset

  # ---------------------------------------------------------------------------
  # Option builders
  # ---------------------------------------------------------------------------

  # Build a single Nix option from a proto field
  mkOptionFromField =
    {
      field,
      allMessages ? { },
    }:
    lib.mkOption {
      type = protoTypeToNix { inherit field allMessages; };
      description = field.description or "";
      default = getFieldDefault field;
    };

  # Build Nix options attrset from a proto message's fields
  # Converts field names from snake_case to kebab-case by default
  mkOptionsFromMessage =
    {
      message,
      allMessages ? { },
      useKebabCase ? true,
    }:
    lib.mapAttrs' (
      fieldName: field:
      let
        nixFieldName = if useKebabCase then snakeToKebab fieldName else fieldName;
      in
      {
        name = nixFieldName;
        value = mkOptionFromField { inherit field allMessages; };
      }
    ) (message.fields or { });

  # Build a submodule type from a proto message
  mkSubmoduleFromMessage =
    {
      message,
      allMessages ? { },
      useKebabCase ? true,
    }:
    lib.types.submodule {
      options = mkOptionsFromMessage { inherit message allMessages useKebabCase; };
    };

  # Build a complete option (with type, description, default) from a proto message
  # This is the main entry point for core/options to use
  mkOptionFromMessage =
    {
      message,
      allMessages ? { },
      useKebabCase ? true,
      description ? message.description or "",
      default ? { },
      example ? null,
    }:
    lib.mkOption {
      type = mkSubmoduleFromMessage { inherit message allMessages useKebabCase; };
      inherit description default;
    }
    // (if example != null then { inherit example; } else { });

  # Build an attrsOf option for map-style messages (like Users, Apps, etc.)
  # Use this when you have a map<string, Entity> pattern
  mkMapOptionFromMessage =
    {
      message, # The value message (e.g., User, App)
      allMessages ? { },
      useKebabCase ? true,
      description ? "",
      default ? { },
      example ? null,
    }:
    lib.mkOption {
      type = lib.types.attrsOf (mkSubmoduleFromMessage {
        inherit message allMessages useKebabCase;
      });
      inherit description default;
    }
    // (if example != null then { inherit example; } else { });

  # ---------------------------------------------------------------------------
  # Schema helpers
  # ---------------------------------------------------------------------------

  # Extract messages from a schema for nested resolution
  getSchemaMessages = schema: schema.messages or { };

  # Build options for an entity given a schema and message name
  # This is a convenience function for the schema registry
  #
  # Usage:
  #   mkEntityOptions {
  #     schema = schemas.users;
  #     messageName = "User";
  #   }
  mkEntityOptions =
    {
      schema,
      messageName,
    }:
    let
      allMessages = getSchemaMessages schema;
    in
    mkOptionsFromMessage {
      message = schema.messages.${messageName} or { fields = { }; };
      inherit allMessages;
    };
in
{
  # String utilities
  inherit snakeToKebab kebabToSnake;

  # Type conversion
  inherit protoTypeToNix getFieldDefault;

  # Option builders
  inherit
    mkOptionFromField
    mkOptionsFromMessage
    mkSubmoduleFromMessage
    mkOptionFromMessage
    mkMapOptionFromMessage
    ;

  # Schema helpers
  inherit getSchemaMessages mkEntityOptions;
}
