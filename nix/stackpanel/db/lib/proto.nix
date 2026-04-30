# ==============================================================================
# nix/stackpanel/db/lib/proto.nix
#
# Protobuf generation library for Nix schemas.
#
# Converts Nix type definitions to Protocol Buffer schema format.
# Output can be used with `buf generate` to create Go, TypeScript,
# Drizzle schemas, tRPC definitions, and more.
#
# ------------------------------------------------------------------------------
# Two APIs are supported for defining fields:
#
# 1. Attribute-set API (RECOMMENDED, feels like lib.mkOption)
# ------------------------------------------------------------------------------
#   proto.mkMessage {
#     name = "User";
#     fields = {
#       name = proto.mkField {
#         number = 1;
#         type = proto.types.string;
#         description = "Display name";
#         default = "anonymous";
#       };
#       email = proto.mkField {
#         number = 2;
#         type = proto.types.string;
#         description = "Email address";
#         example = "john@example.com";
#       };
#       age = proto.mkField {
#         number = 3;
#         type = proto.types.int32;
#         description = "User age";
#         optional = true;
#       };
#       roles = proto.mkField {
#         number = 4;
#         type = proto.types.string;
#         description = "User roles";
#         repeated = true;
#       };
#       profile = proto.mkField {
#         number = 5;
#         type = proto.types.message "Profile";
#         description = "Linked profile";
#       };
#       tags = proto.mkField {
#         number = 6;
#         type = proto.types.map "string" "string";
#         description = "Arbitrary tags";
#       };
#     };
#   }
#
# 2. Positional API (LEGACY, still supported; ~25 existing schemas use it)
# ------------------------------------------------------------------------------
#   fields = {
#     name = proto.string 1 "Display name";
#     email = proto.withExample "john@example.com" (proto.string 2 "Email address");
#     age = proto.optional (proto.int32 3 "User age");
#     roles = proto.repeated (proto.string 4 "User roles");
#   };
#
# Both APIs produce the same field record shape (marked with `_isProtoField`).
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
  # proto.types.*
  #
  # Type spec constructors for the attribute-set API. Each returns either a
  # plain string (scalar / message reference) or an attrset describing a
  # modifier (map key/value). The returned value is consumed by `mkField`.
  #
  # Examples:
  #   proto.types.string                 => "string"
  #   proto.types.int32                  => "int32"
  #   proto.types.message "Foo"          => "Foo"
  #   proto.types.ref "Foo"              => "Foo" (alias for message)
  #   proto.types.map "string" "Foo"     => { _isProtoMapType = true; key = "string"; value = "Foo"; }
  # ---------------------------------------------------------------------------
  types = {
    # Scalars: exposed as plain string type names
    double = scalars.double;
    float = scalars.float;
    int32 = scalars.int32;
    int64 = scalars.int64;
    uint32 = scalars.uint32;
    uint64 = scalars.uint64;
    sint32 = scalars.sint32;
    sint64 = scalars.sint64;
    fixed32 = scalars.fixed32;
    fixed64 = scalars.fixed64;
    sfixed32 = scalars.sfixed32;
    sfixed64 = scalars.sfixed64;
    bool = scalars.bool;
    string = scalars.string;
    bytes = scalars.bytes;

    # Reference another message or enum by name.
    # Usage: proto.types.message "ColorScheme"
    message = typeName: typeName;

    # Alias for message (reads nicely for enum references too)
    ref = typeName: typeName;

    # Map type: proto.types.map "string" "User"
    # Returns a marker attrset so mkField can extract key/value separately.
    map =
      keyType: valueType:
      {
        _isProtoMapType = true;
        key = keyType;
        value = valueType;
      };
  };

  # ---------------------------------------------------------------------------
  # Field definition helpers
  # ---------------------------------------------------------------------------

  # mkField: the primary attribute-set API for defining proto fields.
  #
  # This is the recommended shape for all NEW schemas. It intentionally mirrors
  # `lib.mkOption` so it feels familiar.
  #
  # Required:
  #   number  - Proto field number (REQUIRED, positive integer, explicit for
  #             wire compatibility)
  #   type    - Proto type, provided via `proto.types.*`
  #             (a string like "string", or a map marker from proto.types.map)
  #
  # Optional:
  #   description - Human-readable description (rendered as proto comment
  #                 and used for Nix option docs / UI labels)
  #   default     - Default value for Nix option generators / boilerplate.
  #                 Proto3 wire format has no explicit defaults, so this is
  #                 NOT emitted in `.proto` output. It flows into
  #                 `db.options.mkOptionFromField` so generated Nix options
  #                 can pick it up automatically.
  #   example     - Example value for documentation / UI placeholder
  #   optional    - Proto3 explicit optional modifier
  #   repeated    - Proto repeated modifier
  #   mapKey      - Proto map key type (only use directly if not using
  #                 `proto.types.map`; prefer the latter)
  mkField =
    args:
    let
      # Normalise the `type` argument. It may be:
      #   * a plain string (scalar or message name)
      #   * a map marker attrset from proto.types.map
      rawType = args.type or (throw "proto.mkField: `type` is required (use proto.types.*)");
      isMapSpec = builtins.isAttrs rawType && (rawType._isProtoMapType or false);

      # Explicit mapKey wins, otherwise pick it up from proto.types.map
      explicitMapKey = args.mapKey or null;
      mapKey =
        if explicitMapKey != null then
          explicitMapKey
        else if isMapSpec then
          rawType.key
        else
          null;

      # Resolve the wire/value type string
      typeStr = if isMapSpec then rawType.value else rawType;

      number = args.number or (throw "proto.mkField: `number` is required");
      description = args.description or "";
      optional = args.optional or false;
      repeated = args.repeated or false;
      default = args.default or null;
      example = args.example or null;
    in
    assert
      builtins.isInt number && number >= 1
      || throw "Field number must be a positive integer, got: ${toString number}";
    {
      _isProtoField = true;
      type = typeStr;
      inherit
        number
        description
        optional
        repeated
        mapKey
        example
        default
        ;
    };

  # ---------------------------------------------------------------------------
  # Legacy positional constructors
  #
  # All existing schemas use these; they remain unchanged. They delegate to
  # the new attribute-set `mkField` under the hood so there is a single
  # source of truth for field shape.
  # ---------------------------------------------------------------------------

  # Scalar field constructors: (number -> description -> field)
  string =
    number: description:
    mkField {
      type = types.string;
      inherit number description;
    };
  int32 =
    number: description:
    mkField {
      type = types.int32;
      inherit number description;
    };
  int64 =
    number: description:
    mkField {
      type = types.int64;
      inherit number description;
    };
  uint32 =
    number: description:
    mkField {
      type = types.uint32;
      inherit number description;
    };
  uint64 =
    number: description:
    mkField {
      type = types.uint64;
      inherit number description;
    };
  bool =
    number: description:
    mkField {
      type = types.bool;
      inherit number description;
    };
  double =
    number: description:
    mkField {
      type = types.double;
      inherit number description;
    };
  float =
    number: description:
    mkField {
      type = types.float;
      inherit number description;
    };
  bytes =
    number: description:
    mkField {
      type = types.bytes;
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
        # number must be baked into legacy callers via the scalar helpers;
        # calling optional on a bare string type has never been the path
        # used in schemas, but we preserve the historical (best-effort)
        # behaviour here.
        number = 1;
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
        number = 1;
      };

  # Wrapper to add an example value to a field
  # Usage: proto.withExample "john@example.com" (proto.string 1 "Email address")
  withExample =
    exampleValue: field:
    if field ? _isProtoField then
      field // { example = exampleValue; }
    else
      throw "withExample can only be applied to a proto field";

  # Wrapper to add a default value to a field (positional/legacy style).
  # Usage: proto.withDefault "dracula" (proto.string 1 "Theme name")
  withDefault =
    defaultValue: field:
    if field ? _isProtoField then
      field // { default = defaultValue; }
    else
      throw "withDefault can only be applied to a proto field";

  # Map field constructor
  # Usage: proto.map "string" "User" 1 "description"
  map =
    keyType: valueType: number: description:
    mkField {
      type = valueType;
      mapKey = keyType;
      inherit number description;
    };

  # Reference to another message type (positional style)
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
      # Boilerplate Nix content for scaffolding .stack/config.nix or .stack/data/<name>.nix files
      # Should be a string containing valid Nix that conforms to this schema
      boilerplate ? null,
      # Internal boilerplate for _internal.nix (only used by config schema)
      internalBoilerplate ? null,
      # Consolidated data.nix boilerplate (agent-editable data file)
      dataBoilerplate ? null,
      # .gitignore boilerplate
      gitignoreBoilerplate ? null,
      # Module documentation (markdown) to display in UI panels
      # Helps users understand the module's purpose and configuration options
      readme ? null,
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
        boilerplate
        internalBoilerplate
        dataBoilerplate
        gitignoreBoilerplate
        readme
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

  # Convert kebab-case to snake_case for protobuf compatibility
  kebabToSnake = str: builtins.replaceStrings [ "-" ] [ "_" ] str;

  # Render a single field
  renderField =
    fieldNum: fieldName: field:
    let
      # Convert field name from kebab-case to snake_case for protobuf
      protoFieldName = kebabToSnake fieldName;

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

      # Format an example value for inclusion in proto comments.
      # protobuf-ts emits these comments as JSDoc, so the studio (and any
      # downstream demo/mock agent) can pick examples up via the generated
      # TypeScript types without needing a separate fixtures pipeline.
      #
      # Comments must be single-line and can't contain unescaped quotes that
      # would break proto3 token parsing, so strings get JSON-escaped (which
      # also handles newlines) before being rendered.
      escapeForComment =
        s:
        let
          escaped = builtins.replaceStrings
            [ "\\" "\"" "\n" "\r" "\t" "*/" ]
            [ "\\\\" "\\\"" "\\n" "\\r" "\\t" "*\\/" ]
            s;
        in
        ''"${escaped}"'';
      formatExample =
        v:
        if builtins.isString v then
          escapeForComment v
        else if builtins.isBool v then
          (if v then "true" else "false")
        else if builtins.isInt v || builtins.isFloat v then
          toString v
        else if builtins.isList v then
          "[${lib.concatMapStringsSep ", " formatExample v}]"
        else
          builtins.toJSON v;
      hasExample = (field.example or null) != null;
      exampleStr = lib.optionalString hasExample " (example: ${formatExample field.example})";

      # For multiline descriptions, put comment above the field
      hasMultiline = field.description != "" && lib.hasInfix "\n" field.description;
      descWithExample = field.description + exampleStr;
      blockComment =
        if hasMultiline then
          "  /*\n   * ${lib.concatStringsSep "\n   * " (lib.splitString "\n" descWithExample)}\n   */\n"
        else
          "";
      inlineDesc =
        if field.description == "" then
          (lib.optionalString hasExample "example: ${formatExample field.example}")
        else
          descWithExample;
      inlineComment = lib.optionalString (
        inlineDesc != "" && !hasMultiline
      ) " // ${inlineDesc}";
      num = if field.number != null then field.number else fieldNum;
    in
    "${blockComment}  ${typeStr} ${protoFieldName} = ${toString num};${inlineComment}";

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
      packageLine = "package ${file.package};";

      importLines = builtins.map (i: ''import "${i}";'') file.imports;

      optionLines = lib.mapAttrsToList (
        k: v: if builtins.isString v then ''option ${k} = "${v}";'' else "option ${k} = ${toString v};"
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

  # Type spec constructors for the attribute-set mkField API.
  # This is the RECOMMENDED entrypoint for new schemas.
  inherit types;

  # Scalar field constructors (legacy positional API)
  # Takes: number -> description -> field
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

  # Field modifiers (legacy)
  inherit
    optional
    repeated
    map
    message
    withExample
    withDefault
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
