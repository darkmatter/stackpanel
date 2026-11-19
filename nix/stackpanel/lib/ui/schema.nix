# Interpret the structural vocabulary emitted by the Studio catalog. A descriptor
# pairs a real Nix option type (for editors) with a check on *literal* data: do
# not interpret author JSON as modules (imports, _module, mkIf, etc.). Runtime
# refinements/authorization remain Studio's responsibility.
{ lib, safeKey }:
let
  inherit (lib) types;
  fail = loc: message: throw "${lib.showOption loc}: ${message}";
  checkObject =
    loc: value:
    if builtins.isAttrs value && !(value ? outPath || value ? __toString || value ? __functor) then
      true
    else
      fail loc "expected a plain attribute set";
  fieldsOf = lib.mapAttrs (
    _: field:
    lib.mkOption {
      inherit (field) type;
      description = field.description or field.type.description;
    }
  );
  atom = type: {
    inherit type;
    validate =
      loc: v:
      if type.check v && !(builtins.isString v && builtins.hasContext v) then
        true
      else
        fail loc "expected ${type.description}";
  };
  record = required: fields: {
    options = fieldsOf fields;
    # JSON-derived attributes have no Nix source line. Give nixd a real
    # declaration file instead of the module system's `<unknown-file>`.
    type = types.submodule {
      _file = toString ./widget-catalog.v1.json;
      options = fieldsOf fields;
    };
    validate =
      loc: value:
      let
        names = builtins.attrNames value;
        unknown = lib.findFirst (n: !(fields ? ${n})) null names;
        missing = lib.findFirst (n: !(value ? ${n})) null required;
      in
      builtins.seq (checkObject loc value) (
        if unknown != null then
          fail (
            loc ++ [ unknown ]
          ) "unknown field; expected one of: ${lib.concatStringsSep ", " (builtins.attrNames fields)}"
        else if missing != null then
          fail (loc ++ [ missing ]) "required field is missing"
        else
          lib.all (n: fields.${n}.validate (loc ++ [ n ]) value.${n}) names
      );
  };
  dict = field: {
    type = types.attrsOf field.type;
    validate =
      loc: value:
      builtins.seq (checkObject loc value) (
        lib.all (
          n:
          if safeKey n then
            field.validate (loc ++ [ n ]) value.${n}
          else
            fail (loc ++ [ n ]) "expected a safe identifier"
        ) (builtins.attrNames value)
      );
  };
  array = schema: item: {
    type = types.listOf item.type;
    validate =
      loc: value:
      if !builtins.isList value then
        fail loc "expected a list of ${item.type.description}"
      else if schema ? minItems && builtins.length value < schema.minItems then
        fail loc "expected at least ${toString schema.minItems} entries"
      else if schema ? maxItems && builtins.length value > schema.maxItems then
        fail loc "expected at most ${toString schema.maxItems} entries"
      else
        lib.all lib.id (lib.imap0 (i: v: item.validate (loc ++ [ "[${toString i}]" ]) v) value);
  };
  union =
    branches:
    let
      type = types.oneOf (map (d: d.type) branches);
    in
    {
      inherit type;
      validate =
        loc: v:
        let
          matches = builtins.filter (d: d.type.check v) branches;
        in
        if builtins.length matches == 1 then
          (builtins.head matches).validate loc v
        else if lib.any (d: (builtins.tryEval (d.validate loc v)).success) matches then
          true
        else
          fail loc "expected ${type.description}";
    };
  # Zod counts JavaScript UTF-16 units; Nix stringLength counts UTF-8 bytes.
  # Only count leading bytes (astral characters count twice) in the slow path.
  withinLength =
    limit: s:
    builtins.stringLength s <= limit
    || (
      builtins.stringLength s <= 3 * limit
      &&
        lib.foldl' (
          n: byte:
          n
          + (
            if byte >= builtins.substring 0 1 "𐀀" then
              2 # 0xf0: four-byte sequence
            else if byte < builtins.substring 1 1 "Ā" then
              1 # 0x80: ASCII
            else if byte >= builtins.substring 0 1 "¢" then
              1 # 0xc2: two/three-byte lead
            else
              0
          ) # continuation byte
        ) 0 (lib.stringToCharacters s) <= limit
    );
  fromSchema =
    schema:
    let
      shape =
        if schema ? anyOf then
          union (map fromSchema schema.anyOf)
        else if schema ? const then
          atom (types.enum [ schema.const ])
        else if schema ? enum then
          atom (types.enum schema.enum)
        else if schema.type == "object" && builtins.isAttrs (schema.additionalProperties or null) then
          dict (fromSchema schema.additionalProperties)
        else if schema.type == "object" && schema.additionalProperties == false then
          record (schema.required or [ ]) (lib.mapAttrs (_: fromSchema) schema.properties)
        else if schema.type == "array" then
          array schema (fromSchema schema.items)
        else if schema.type == "string" && schema ? maxLength then
          atom (
            (types.addCheck types.str (withinLength schema.maxLength))
            // {
              description = "string of at most ${toString schema.maxLength} UTF-16 units";
            }
          )
        else if schema.type == "string" then
          atom types.str
        else if schema.type == "number" then
          atom types.number
        else if schema.type == "integer" then
          atom types.int
        else if schema.type == "null" then
          atom (types.enum [ null ])
        else if schema.type == "boolean" then
          atom types.bool
        else
          throw "Unsupported Studio catalog schema: ${builtins.toJSON schema}";
    in
    shape // lib.optionalAttrs (schema ? description) { inherit (schema) description; };
in
{
  inherit
    atom
    array
    checkObject
    dict
    fail
    fromSchema
    record
    ;
}
