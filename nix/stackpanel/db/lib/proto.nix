# ==============================================================================
# nix/stackpanel/db/lib/proto.nix
#
# Protobuf generation library for Nix schemas.
#
# Converts Nix type definitions to Protocol Buffer schema format.
# Output can be used with `buf generate` to create Go, TypeScript,
# Drizzle schemas, tRPC definitions, and more.
#
# Usage:
#   let
#     proto = import ./proto.nix { inherit lib; };
#   in
#   proto.mkMessage {
#     name = "User";
#     fields = {
#       name = proto.string "Display name";
#       email = proto.string "Email address";
#       age = proto.optional proto.int32 "User age";
#       roles = proto.repeated proto.string "User roles";
#     };
#   }
#
# Type mapping:
#   Nix types           → Protobuf
#   ─────────────────────────────────
#   types.str           → string
#   types.int           → int64
#   types.bool          → bool
#   types.float         → double
#   types.listOf T      → repeated T
#   types.attrsOf T     → map<string, T>
#   types.nullOr T      → optional T
#   types.enum [...]    → enum
#   types.submodule     → message
# ==============================================================================
{ lib }:
let
  # ---------------------------------------------------------------------------
  # Protobuf scalar types
  # ---------------------------------------------------------------------------
  scalars = {
    double = "double";
    float = "float";
    int32 = "int32";
    int64 = "int64";
    uint32 = "uint32";
    uint64 = "uint64";
    sint32 = "sint32";
    sint64 = "sint64";
    fixed32 = "fixed32";
    fixed64 = "fixed64";
    sfixed32 = "sfixed32";
    sfixed64 = "sfixed64";
    bool = "bool";
    string = "string";
    bytes = "bytes";
  };

  # ---------------------------------------------------------------------------
  # Field definition helpers
  # ---------------------------------------------------------------------------

  # Create a basic field
  # Field number is REQUIRED - protobuf field numbers must be explicit for compatibility
  mkField =
    {
      type,
      number, # Field number (REQUIRED - must be explicit for protobuf compatibility)
      description ? "",
      optional ? false,
      repeated ? false,
      mapKey ? null, # If set, this is a map<mapKey, type>
    }:
    assert
      builtins.isInt number && number >= 1
      || throw "Field number must be a positive integer, got: ${toString number}";
    {
      inherit
        type
        description
        number
        optional
        repeated
        mapKey
        ;
      _isProtoField = true;
    };

  # Scalar field constructors
  # All take: number -> description -> field
  string =
    number: description:
    mkField {
      type = "string";
      inherit number description;
    };
  int32 =
    number: description:
    mkField {
      type = "int32";
      inherit number description;
    };
  int64 =
    number: description:
    mkField {
      type = "int64";
      inherit number description;
    };
  uint32 =
    number: description:
    mkField {
      type = "uint32";
      inherit number description;
    };
  uint64 =
    number: description:
    mkField {
      type = "uint64";
      inherit number description;
    };
  bool =
    number: description:
    mkField {
      type = "bool";
      inherit number description;
    };
  double =
    number: description:
    mkField {
      type = "double";
      inherit number description;
    };
  float =
    number: description:
    mkField {
      type = "float";
      inherit number description;
    };
  bytes =
    number: description:
    mkField {
      type = "bytes";
      inherit number description;
    };

  # Wrapper for optional fields (proto3 explicit optional)
  optional =
    field:
    if field ? _isProtoField then
      field // { optional = true; }
    else
      mkField {
        type = field;
        optional = true;
      };

  # Wrapper for repeated fields
  repeated =
    field:
    if field ? _isProtoField then
      field // { repeated = true; }
    else
      mkField {
        type = field;
        repeated = true;
      };

  # Map field constructor
  # Usage: proto.map "string" "User" 1 "description"
  map =
    keyType: valueType: number: description:
    mkField {
      type = valueType;
      mapKey = keyType;
      inherit number description;
    };

  # Reference to another message type
  # Usage: proto.message "TypeName" 1 "description"
  message =
    typeName: number: description:
    mkField {
      type = typeName;
      inherit number description;
    };

  # ---------------------------------------------------------------------------
  # Enum definition
  # ---------------------------------------------------------------------------
  mkEnum =
    {
      name,
      values, # List of strings or attrset { name = number; }
      description ? "",
      allowAlias ? false,
    }:
    let
      # Convert list of strings to attrset with auto-numbered values
      valuesAttrs =
        if builtins.isList values then
          lib.listToAttrs (
            lib.imap0 (i: v: {
              name = v;
              value = i;
            }) values
          )
        else
          values;
    in
    {
      _isProtoEnum = true;
      inherit name description allowAlias;
      values = valuesAttrs;
    };

  # ---------------------------------------------------------------------------
  # Message definition
  # ---------------------------------------------------------------------------
  mkMessage =
    {
      name,
      fields, # Attrset of field name -> field definition
      description ? "",
      nested ? { }, # Nested messages/enums
    }:
    {
      _isProtoMessage = true;
      inherit
        name
        fields
        description
        nested
        ;
    };

  # ---------------------------------------------------------------------------
  # Service definition (for tRPC/gRPC)
  # ---------------------------------------------------------------------------
  mkService =
    {
      name,
      methods, # Attrset of method name -> { input, output, description? }
      description ? "",
    }:
    {
      _isProtoService = true;
      inherit name methods description;
    };

  mkMethod =
    {
      input,
      output,
      description ? "",
      streaming ? null, # null | "client" | "server" | "bidirectional"
    }:
    {
      _isProtoMethod = true;
      inherit
        input
        output
        description
        streaming
        ;
    };

  # ---------------------------------------------------------------------------
  # Proto file definition
  # ---------------------------------------------------------------------------
  mkProtoFile =
    {
      name,
      package,
      messages ? { },
      enums ? { },
      services ? { },
      imports ? [ ],
      options ? { },
      syntax ? "proto3",
    }:
    {
      _isProtoFile = true;
      inherit
        name
        package
        messages
        enums
        services
        imports
        options
        syntax
        ;
    };

  # ---------------------------------------------------------------------------
  # Rendering functions - convert Nix structures to .proto text
  # ---------------------------------------------------------------------------

  # Indent a multi-line string
  indent =
    n: text:
    let
      spaces = lib.concatStrings (lib.replicate n "  ");
    in
    lib.concatMapStringsSep "\n" (line: if line == "" then "" else "${spaces}${line}") (
      lib.splitString "\n" text
    );

  # Render a comment block (handles multiline with block comments)
  renderComment =
    description:
    if description == "" then
      ""
    else if lib.hasInfix "\n" description then
      "/*\n * ${lib.concatStringsSep "\n * " (lib.splitString "\n" description)}\n */\n"
    else
      "// ${description}\n";

  # Render an enum
  renderEnum =
    enum:
    let
      # Convert to list and sort by numeric value (proto3 requires first value = 0)
      valuesList = lib.mapAttrsToList (name: num: { inherit name num; }) enum.values;
      sortedValues = lib.sort (a: b: a.num < b.num) valuesList;
      valueLines = builtins.map (v: "  ${lib.toUpper v.name} = ${toString v.num};") sortedValues;
      aliasOption = lib.optionalString enum.allowAlias "  option allow_alias = true;\n";
    in
    ''
      ${renderComment enum.description}enum ${enum.name} {
      ${aliasOption}${lib.concatStringsSep "\n" valueLines}
      }
    '';

  # Render a single field
  renderField =
    fieldNum: fieldName: field:
    let
      # Build the type string
      typeStr =
        if field.mapKey != null then
          "map<${field.mapKey}, ${field.type}>"
        else if field.repeated then
          "repeated ${field.type}"
        else if field.optional then
          "optional ${field.type}"
        else
          field.type;

      # For multiline descriptions, put comment above the field
      hasMultiline = field.description != "" && lib.hasInfix "\n" field.description;
      blockComment =
        if hasMultiline then
          "  /*\n   * ${lib.concatStringsSep "\n   * " (lib.splitString "\n" field.description)}\n   */\n"
        else
          "";
      inlineComment = lib.optionalString (
        field.description != "" && !hasMultiline
      ) " // ${field.description}";
      num = if field.number != null then field.number else fieldNum;
    in
    "${blockComment}  ${typeStr} ${fieldName} = ${toString num};${inlineComment}";

  # Render a message
  renderMessage =
    msg:
    let
      # Render nested types first
      nestedEnums = lib.mapAttrsToList (_: renderEnum) (
        lib.filterAttrs (_: v: v._isProtoEnum or false) msg.nested
      );
      nestedMessages = lib.mapAttrsToList (_: renderMessage) (
        lib.filterAttrs (_: v: v._isProtoMessage or false) msg.nested
      );
      nestedContent = lib.concatStringsSep "\n" (nestedEnums ++ nestedMessages);

      # Render fields (sorted by field number for readability)
      fieldsList = lib.mapAttrsToList (name: value: { inherit name value; }) msg.fields;
      sortedFields = lib.sort (a: b: a.value.number < b.value.number) fieldsList;
      fieldLines = builtins.map (f: renderField f.value.number f.name f.value) sortedFields;

      content = lib.concatStringsSep "\n" (
        (lib.optional (nestedContent != "") (indent 1 nestedContent)) ++ fieldLines
      );
    in
    ''
      ${renderComment msg.description}message ${msg.name} {
      ${content}
      }
    '';

  # Render a service method
  renderMethod =
    methodName: method:
    let
      inputStream =
        if method.streaming == "client" || method.streaming == "bidirectional" then "stream " else "";
      outputStream =
        if method.streaming == "server" || method.streaming == "bidirectional" then "stream " else "";
      comment = renderComment method.description;
    in
    "  ${comment}rpc ${methodName}(${inputStream}${method.input}) returns (${outputStream}${method.output});";

  # Render a service
  renderService =
    svc:
    let
      methodLines = lib.mapAttrsToList renderMethod svc.methods;
    in
    ''
      ${renderComment svc.description}service ${svc.name} {
      ${lib.concatStringsSep "\n" methodLines}
      }
    '';

  # Render a complete .proto file
  renderProtoFile =
    file:
    let
      syntaxLine = ''syntax = "${file.syntax}";'';
      packageLine = ''package ${file.package};'';

      importLines = builtins.map (i: ''import "${i}";'') file.imports;

      optionLines = lib.mapAttrsToList (
        k: v: if builtins.isString v then ''option ${k} = "${v}";'' else ''option ${k} = ${toString v};''
      ) file.options;

      enumBlocks = lib.mapAttrsToList (_: renderEnum) file.enums;
      messageBlocks = lib.mapAttrsToList (_: renderMessage) file.messages;
      serviceBlocks = lib.mapAttrsToList (_: renderService) file.services;

      sections = [
        syntaxLine
        ""
        packageLine
      ]
      ++ (lib.optional (importLines != [ ]) (lib.concatStringsSep "\n" importLines))
      ++ (lib.optional (optionLines != [ ]) (lib.concatStringsSep "\n" optionLines))
      ++ [ "" ]
      ++ enumBlocks
      ++ messageBlocks
      ++ serviceBlocks;
    in
    lib.concatStringsSep "\n" (lib.filter (x: x != null) sections);

  # ---------------------------------------------------------------------------
  # Nix types to Protobuf conversion helpers
  # ---------------------------------------------------------------------------

  # Convert a Nix lib.types.* to protobuf type
  nixTypeToProto =
    type:
    let
      typeName = type.name or (if type ? functor.name then type.functor.name else "unknown");
    in
    {
      "str" = "string";
      "string" = "string";
      "int" = "int64";
      "ints" = "int64";
      "bool" = "bool";
      "boolean" = "bool";
      "float" = "double";
      "number" = "double";
      "path" = "string";
    }
    .${typeName} or "string";

  # ---------------------------------------------------------------------------
  # High-level schema builder (similar to mkSchema in types.nix)
  # ---------------------------------------------------------------------------
  mkProtoSchema =
    {
      name,
      package,
      description ? "",
      fields ? { },
      enums ? { },
      nested ? { },
    }:
    let
      mainMessage = mkMessage {
        inherit name description nested;
        fields = lib.mapAttrs (
          fieldName: fieldDef: if fieldDef ? _isProtoField then fieldDef else mkField fieldDef
        ) fields;
      };
    in
    mkProtoFile {
      name = "${lib.toLower name}.proto";
      inherit package enums;
      messages.${name} = mainMessage;
    };

in
{
  # Scalar type names (raw strings for manual use)
  scalars = scalars;

  # Field constructors (functions that take description and return field definitions)
  inherit
    string
    int32
    int64
    uint32
    uint64
    bool
    double
    float
    bytes
    ;

  # Field modifiers
  inherit
    optional
    repeated
    map
    message
    ;

  # Type constructors
  inherit
    mkField
    mkEnum
    mkMessage
    mkService
    mkMethod
    mkProtoFile
    ;

  # High-level builder
  inherit mkProtoSchema;

  # Renderers
  inherit
    renderEnum
    renderMessage
    renderService
    renderProtoFile
    ;

  # Utilities
  inherit nixTypeToProto indent;
}
