# jsonSchemaFromSpFields :: { <name> = SpField | option | { ... }; } -> String
# Input is a tree of declarations, not an evaluated configuration. A settings
# descriptor ({ type = lib.types.*; ... }) is also an option for this purpose.
{ lib }:
let
  inherit (lib) optionalAttrs;
  sp = import ../db/lib/field.nix { inherit lib; };

  # Decide whether to inspect defaults *from the type*, not by inspecting the
  # default and testing isDerivation. Even forcing pkgs.foo to WHNF can fail
  # in global eval. Propagate this through lists, maps and unions of packages.
  projection = literals: schema: { inherit literals schema; };
  literal = projection true;
  opaque = projection false;

  # Nix docs can use literalExpression/literalMD in lieu of a real example.
  # Nor should toJSON implicitly coerce paths, derivations or contextual strings.
  isLiteral =
    value:
    if builtins.isAttrs value then
      !(value ? outPath || value ? __toString || value ? __functor)
      && !(builtins.elem (value._type or null) [
        "literalExpression"
        "literalMD"
      ])
      && lib.all isLiteral (builtins.attrValues value)
    else if builtins.isList value then
      lib.all isLiteral value
    else if builtins.isString value then
      !(builtins.hasContext value)
    else
      builtins.elem (builtins.typeOf value) [
        "bool"
        "float"
        "int"
        "null"
      ];

  enumSchema =
    values:
    let
      enum = lib.unique values;
    in
    if enum == [ ] then
      { not = { }; }
    else
      {
        inherit enum;
      }
      // (
        if lib.all builtins.isString enum then
          { type = "string"; }
        else if lib.all builtins.isInt enum then
          { type = "integer"; }
        else if lib.all builtins.isBool enum then
          { type = "boolean"; }
        else
          { }
      );

  nullable =
    schema:
    if schema ? type then
      schema
      // {
        type = lib.unique (lib.toList schema.type ++ [ "null" ]);
      }
      // optionalAttrs (schema ? enum) { enum = lib.unique (schema.enum ++ [ null ]); }
    else
      {
        anyOf = [
          schema
          { type = "null"; }
        ];
      };

  string = literal { type = "string"; };
  boolean = literal { type = "boolean"; };
  integer = literal { type = "integer"; };
  number = literal { type = "number"; };

  # ints.between / numbers.between expose their bounds in the description,
  # not in the functor payload. This includes e.g. types.port (ints.u16).
  bounded =
    type: base:
    let
      bounds = builtins.match ".*between ([-+0-9.eE]+) and ([-+0-9.eE]+) \\(both inclusive\\)" type.description;
    in
    literal (
      base.schema
      // optionalAttrs (bounds != null) {
        minimum = builtins.fromJSON (builtins.elemAt bounds 0);
        maximum = builtins.fromJSON (builtins.elemAt bounds 1);
      }
    );

  fromType =
    path: type:
    let
      inherit (type) name;
      nested = type.nestedTypes;
      convert = fromType path;
      elem = convert nested.elemType;
      mapType = projection elem.literals {
        type = "object";
        additionalProperties = elem.schema;
      };
      union =
        a: b:
        projection (a.literals && b.literals) {
          anyOf = [
            a.schema
            b.schema
          ];
        };
      types = {
        str = string;
        separatedString = string;
        singleLineStr = literal {
          type = "string";
          pattern = "^[^\\r\\n]*\\n?$";
        };
        nonEmptyStr = literal {
          type = "string";
          pattern = "[^ \\t\\n]";
        };
        bool = boolean;
        boolByOr = boolean;
        int = integer;
        float = number;
        unsignedInt = literal {
          type = "integer";
          minimum = 0;
        };
        positiveInt = literal {
          type = "integer";
          minimum = 1;
        };
        intBetween = bounded type integer;
        numberBetween = bounded type number;
        numberNonnegative = literal {
          type = "number";
          minimum = 0;
        };
        numberPositive = literal {
          type = "number";
          exclusiveMinimum = 0;
        };
        path = opaque {
          type = "string";
          format = "path";
        };
        package = opaque {
          type = "string";
          format = "nix-store-path";
        };
        attrs = opaque { type = "object"; };
        anything = opaque { };
        raw = opaque { };
        unspecified = opaque { };
        functionTo = opaque { not = { }; };
        enum = literal (enumSchema type.functor.payload.values);
        listOf = projection elem.literals (
          {
            type = "array";
            items = elem.schema;
          }
          # nonEmptyListOf retains the listOf name but removes its empty value.
          // optionalAttrs (!(type.emptyValue ? value)) { minItems = 1; }
        );
        attrsOf = mapType;
        lazyAttrsOf = mapType;
        unique = elem;
        nullOr = projection elem.literals (nullable elem.schema);
        either =
          if nested.left.name == "int" && nested.right.name == "float" then
            number
          else
            union (convert nested.left) (convert nested.right);
        coercedTo = union (convert nested.coercedType) (convert nested.finalType);
        submodule =
          let
            options = removeAttrs (type.getSubOptions path) [
              "_module"
              "_freeformOptions"
            ];
            object = (fromTree path options).schema;
          in
          opaque (
            object
            // optionalAttrs (nested ? freeformType) {
              additionalProperties = (convert nested.freeformType).schema.additionalProperties or true;
            }
          );
      };
    in
    types.${name} or (
      if builtins.match "(un)?signedInt(8|16|32)" name != null then
        bounded type integer
      else if type.functor.name == "strMatching" then
        # Nix matches an entire POSIX ERE. Do not impose a non-equivalent JS regexp.
        literal {
          type = "string";
          "x-nix-pattern" = type.functor.payload.pattern;
        }
      # An arbitrary mkOptionType.check is Nix code, not a JSON constraint.
      else
        opaque { "x-nix-type" = name; }
    );

  fromOption =
    path: option:
    let
      projected = fromType path (option.type or lib.types.unspecified);
      description = option.description or null;
      readOnly = option.readOnly or false;
    in
    {
      required = !(option ? default) && !readOnly;
      schema =
        projected.schema
        // optionalAttrs (builtins.isString description && description != "") { inherit description; }
        // optionalAttrs readOnly { inherit readOnly; }
        //
          optionalAttrs
            (projected.literals && option ? default && !(option ? defaultText) && isLiteral option.default)
            {
              inherit (option) default;
            }
        // optionalAttrs (projected.literals && option ? example && isLiteral option.example) {
          examples = [ option.example ];
        };
    };

  fromField =
    path: field:
    let
      # Share the actual type/modifier precedence and explicit/inferred default
      # logic with the module system, rather than guessing from the proto type.
      option = fromOption path (sp.asOption field);
      inherit (field) ui;
    in
    option
    // {
      schema =
        option.schema
        // {
          # Select options are UI suggestions, not a Nix enum. Keep their labels
          # (and hidden fields) without narrowing what the option accepts.
          "x-stackpanel-ui" = if ui == null then null else removeAttrs ui [ "example" ];
        }
        // optionalAttrs (ui != null && ui.label != "") { title = ui.label; }
        // optionalAttrs (ui != null && !ui.editable) { readOnly = true; }
        // optionalAttrs (ui != null && ui.example != null && isLiteral ui.example) {
          examples = [ ui.example ];
        };
    };

  fromNode =
    path: node:
    if !builtins.isAttrs node then
      throw "jsonSchemaFromSpFields: expected an option or namespace at ${lib.showOption path}"
    else if (node._isSpField or false) then
      fromField path node
    else if lib.isOption node || (node.type._type or null) == "option-type" then
      fromOption path node
    else
      fromTree path node;

  fromTree =
    path: tree:
    let
      children = lib.mapAttrs (name: fromNode (path ++ [ name ])) tree;
      required = builtins.attrNames (lib.filterAttrs (_: child: child.required) children);
    in
    {
      required = required != [ ];
      schema = {
        type = "object";
        properties = lib.mapAttrs (_: child: child.schema) children;
        additionalProperties = false;
      }
      // optionalAttrs (required != [ ]) { inherit required; };
    };
  # Capability schemas are validation contracts, not form hints: never
  # inspect defaults/examples and never substitute a permissive schema for
  # an opaque type. Option namespaces are closed objects; maps and lists
  # retain their declared element schemas even when currently empty.
  writableSchema =
    node:
    if lib.isOption node then
      let
        p = fromType node.loc node.type;
        supported =
          s:
          !(s ? "x-nix-pattern" || s ? not)
          && isLiteral (s.enum or [ ])
          && (!(s ? items) || supported s.items)
          && (!(s ? additionalProperties) || supported s.additionalProperties)
          && lib.all supported (s.anyOf or [ ]);
      in
      if node.readOnly or false || node.internal or false || !p.literals || !(supported p.schema) then
        null
      else
        p.schema
    else
      let
        properties = lib.mapAttrs (_: writableSchema) node;
        required = builtins.attrNames (
          lib.filterAttrs (_: child: lib.isOption child && !(child ? default)) node
        );
      in
      if properties == { } || lib.any (schema: schema == null) (lib.attrValues properties) then
        null
      else
        {
          type = "object";
          inherit properties;
          additionalProperties = false;
        }
        // optionalAttrs (required != [ ]) { inherit required; };

in
{
  inherit isLiteral writableSchema;
  jsonSchemaFromSpFields =
    tree:
    let
      # evalModules adds this namespace even if there are no settings at all.
      root = fromTree [ ] (removeAttrs tree [ "_module" ]);
    in
    builtins.toJSON (root.schema // { "$schema" = "http://json-schema.org/draft-07/schema#"; });
}
