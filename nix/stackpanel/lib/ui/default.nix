{ lib }:
let
  manifest = lib.importJSON ./widget-catalog.v1.json;
  inherit (manifest) limits;
  safeKey = import ./safe-key.nix;
  schema = import ./schema.nix { inherit lib safeKey; };
  binding = import ./bindings.nix { inherit lib schema safeKey; };
  treeRoot = import ./tree.nix { inherit lib limits safeKey; };
  inherit (schema)
    atom
    array
    dict
    fail
    fromSchema
    record
    ;
  inherit (lib) types;
  inherit (import ../json-schema.nix { inherit lib; }) isLiteral;

  kinds =
    assert manifest.version == 1;
    lib.mapAttrs' (
      name: component:
      lib.nameValuePair (lib.toLower (builtins.substring 0 1 name) + builtins.substring 1 (-1) name) (
        component // { nativeType = name; }
      )
    ) manifest.components;
  children = (array { maxItems = limits.maxElements; } (atom types.str)) // {
    description = "Child widget IDs, in display order.";
  };
  kindShape =
    state: kind:
    let
      props = lib.mapAttrs (
        name: prop:
        let
          literal = fromSchema prop;
        in
        if kind.bindings ? ${name} then binding state kind.bindings.${name} literal else literal
      ) kind.props.properties;
    in
    (record (kind.props.required or [ ]) (
      props // lib.optionalAttrs kind.container { inherit children; }
    ))
    // {
      inherit (kind) description;
    };
  widget =
    state:
    let
      shape = record [ ] (lib.mapAttrs (_: kindShape state) kinds);
    in
    shape
    // {
      validate =
        loc: value:
        builtins.seq (schema.checkObject loc value) (
          if builtins.length (builtins.attrNames value) != 1 then
            fail loc "define exactly one widget kind; choose one of: ${lib.concatStringsSep ", " (builtins.attrNames kinds)}"
          else
            shape.validate loc value
        );
    };
  stateShape = fromSchema manifest.state;
  document =
    state:
    let
      widgets = dict (widget state);
    in
    record [ "widgets" ] {
      root = (atom types.str) // {
        description = "Root widget ID. Omit to infer the tree's unique root.";
      };
      widgets = widgets // {
        description = "Named native Studio widgets. Declare exactly one catalog kind per widget.";
        validate =
          loc: value:
          if builtins.isAttrs value && builtins.length (builtins.attrNames value) > limits.maxElements then
            fail loc "use at most ${toString limits.maxElements} widgets"
          else
            widgets.validate loc value;
      };
      state = stateShape // {
        description = "Public data and initial panel-local state.";
      };
    };

  compileAt =
    loc: input:
    let
      shape = document (input.state or { });
      elements = lib.mapAttrs (
        _: entry:
        let
          kind = builtins.head (builtins.attrNames entry);
          props = entry.${kind};
        in
        {
          type = kinds.${kind}.nativeType;
          props = removeAttrs props [ "children" ];
        }
        // lib.optionalAttrs (props ? children) { inherit (props) children; }
      ) input.widgets;
      root = treeRoot loc (input.root or null) elements;
    in
    builtins.seq (shape.validate loc input) (
      builtins.seq root (
        { inherit root elements; } // lib.optionalAttrs (input ? state) { inherit (input) state; }
      )
    );

  # A raw document remains a separate wire format. Studio validates the native
  # elements, not the Nix author DSL. Do not implicitly stringify nested paths.
  rawDocument =
    loc: input:
    let
      unknown = lib.findFirst (
        k:
        !(builtins.elem k [
          "root"
          "elements"
          "state"
        ])
      ) null (builtins.attrNames input);
    in
    builtins.seq (schema.checkObject loc input) (
      if unknown != null then
        fail (loc ++ [ unknown ]) "unknown raw document field; use root, elements and optional state"
      else if !builtins.isString (input.root or null) then
        fail (loc ++ [ "root" ]) "raw document requires a root widget ID"
      else if !builtins.isAttrs (input.elements or null) then
        fail (loc ++ [ "elements" ]) "raw document requires an elements object"
      else if !isLiteral input then
        fail loc "raw document must contain only plain JSON"
      else
        input
    );
  normalize =
    loc: input:
    if input == null then
      null
    else if builtins.isPath input then
      rawDocument loc (lib.importJSON input)
    else if input ? elements && input ? widgets then
      fail loc "cannot mix raw elements with typed widgets"
    else if input ? elements then
      rawDocument loc input
    else
      compileAt loc input;

  authorDeclarations = (document { }).options // {
    state = stateShape.options;
  };
  specOption = lib.mkOption {
    type = lib.mkOptionType {
      # nixd descends through `submodule`, but not `nullOr`/`either`. Expose
      # the author submodule while keeping null/path/raw coercion at this one
      # boundary. Like the original spec option, a document has one owner.
      name = "submodule";
      description = "typed Studio widgets, raw Studio document, JSON file path, or null";
      check = v: v == null || builtins.isPath v || builtins.isAttrs v;
      inherit
        (types.submodule {
          _file = toString ./default.nix;
          options = authorDeclarations;
        })
        getSubOptions
        ;
      merge = loc: defs: normalize loc (lib.mergeOneOption loc defs);
    };
    default = null;
    description = "Native Studio panel. Define typed widgets here or supply a raw document with root and elements. Cannot be combined with a UI bundle.";
    example = lib.literalExpression "./studio.json";
  };
  authorOptions =
    (lib.evalModules {
      modules = [
        {
          _file = toString ./default.nix;
          options.ui = authorDeclarations;
          options.panels = lib.mkOption {
            type = types.attrsOf (
              types.submodule {
                _file = toString ./default.nix;
                options.spec = specOption;
              }
            );
            description = "Explicit native panel declarations.";
          };
        }
      ];
    }).options;
in
{
  inherit specOption;
  moduleAuthorOptions = { inherit (authorOptions) ui panels; };
  ui = lib.mapAttrs (kind: _: props: { ${kind} = props; }) kinds // {
    compile = compileAt [ "ui" ];
    read = path: { "$state" = path; };
    bindLocal = key: { "$bindState" = "/local/${key}"; };
  };
}
