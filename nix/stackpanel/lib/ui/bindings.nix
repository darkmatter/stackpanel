{
  lib,
  schema,
  safeKey,
}:
state: mode: literal:
let
  inherit (schema) atom fail record;
  inherit (lib) types;
  write = mode == "bindLocal";
  directive = if write then "$bindState" else "$state";
  scopes =
    {
      read = [
        "data"
        "local"
      ];
      data = [ "data" ];
      local = [ "local" ];
      bindLocal = [ "local" ];
    }
    .${mode};
  hostPaths = [
    "/module/id"
    "/panel/title"
    "/app/id"
  ];
  hint = lib.concatStringsSep " or " (
    map (scope: "/${scope}/<key>") scopes ++ lib.optionals (mode == "read") hostPaths
  );
  parsePath = path: builtins.match "/(data|local)/([^/]+)" path;
  validPath =
    path:
    (mode == "read" && builtins.elem path hostPaths)
    || (
      let
        parts = parsePath path;
      in
      parts != null && builtins.elem (lib.head parts) scopes && safeKey (lib.last parts)
    );
  reference = record [ directive ] {
    ${directive} = atom ((types.addCheck types.str validPath) // { description = hint; });
  };
  type = if write then reference.type else types.either literal.type reference.type;
in
{
  inherit (literal) description;
  type = type // {
    description =
      if write then "ui.bindLocal <key>" else "${literal.type.description} or ui.read (${hint})";
  };
  validate =
    loc: value:
    if write || (builtins.isAttrs value && (value ? "$state" || value ? "$bindState")) then
      builtins.seq (reference.validate loc value) (
        let
          path = value.${directive};
          parts = parsePath path;
          resolved =
            if parts == null then
              ""
            else
              state.${lib.head parts}.${lib.last parts} or (fail (
                loc ++ [ directive ]
              ) "unknown state path ${path}; declare it in state.${lib.head parts}");
        in
        literal.validate loc resolved
      )
    else
      literal.validate loc value;
}
