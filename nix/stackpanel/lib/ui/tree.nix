# Validate topology only. The typed compiler owns props and child slots; the
# result is just an ID, so neither the flat elements nor child order changes.
{
  lib,
  limits,
  safeKey,
}:
loc: root: elements:
let
  maxWidgets = limits.maxElements;
  maxLevels = limits.maxDepth;

  safeId = safeKey;
  idHint = "use a non-reserved widget ID matching [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}";
  compose = "Compose widgets explicitly with stack.children or section.children, listing child IDs in display order.";
  widgetLoc = loc ++ [ "widgets" ];
  widgetsPath = lib.showOption widgetLoc;
  widgetPath = id: lib.showOption (widgetLoc ++ [ id ]);
  rootPath = lib.showOption (loc ++ [ "root" ]);
  edgePath =
    { parent, index, ... }:
    let
      type = elements.${parent}.type;
      kind = lib.toLower (builtins.substring 0 1 type) + builtins.substring 1 (-1) type;
    in
    "${
      lib.showOption (
        widgetLoc
        ++ [
          parent
          kind
          "children"
        ]
      )
    }[${toString index}]";

  ids = builtins.attrNames elements;
  count = builtins.length ids;
  badId = lib.findFirst (id: !(safeId id)) null ids;
  childrenOf = id: elements.${id}.children or [ ];

  # Index incoming edges once, retaining both use sites for conflict errors.
  incoming =
    builtins.groupBy
      (
        edge:
        if !(safeId edge.child) then
          throw "${edgePath edge}: ${idHint}"
        else if !(builtins.hasAttr edge.child elements) then
          throw "${edgePath edge}: missing child '${edge.child}'; define ${widgetPath edge.child} or correct the reference"
        else
          edge.child
      )
      (
        lib.concatMap (
          parent: lib.imap0 (index: child: { inherit parent index child; }) (childrenOf parent)
        ) ids
      );
  repeated = lib.findFirst (id: builtins.length (incoming.${id} or [ ]) > 1) null ids;
  roots = builtins.filter (id: !(builtins.hasAttr id incoming)) ids;
  chosen = if root == null then builtins.head roots else root;

  # With at most one incoming edge per widget, a component without a root
  # contains a cycle. Following count parents lands *on* it even from a leaf.
  cycleError =
    reason: start:
    let
      ascend = n: id: if n == 0 then id else ascend (n - 1) (builtins.head incoming.${id}).parent;
      child = ascend count start;
    in
    throw "${
      edgePath (builtins.head incoming.${child})
    }: ${reason}; remove the cycle edge to '${child}'. ${compose}";

  reached = builtins.genericClosure {
    startSet = [
      {
        key = chosen;
        level = 1;
      }
    ];
    operator =
      { key, level }:
      let
        children = childrenOf key;
      in
      if level == maxLevels && children != [ ] then
        throw "${
          edgePath {
            parent = key;
            index = 0;
          }
        }: tree exceeds ${toString maxLevels} levels; move this child closer to the root"
      else
        map (child: {
          key = child;
          level = level + 1;
        }) children;
  };
in
if count == 0 then
  throw "${widgetsPath}: empty tree; define at least one widget"
else if count > maxWidgets then
  throw "${widgetsPath}: use at most ${toString maxWidgets} widgets (found ${toString count})"
else if badId != null then
  throw "${widgetPath badId}: ${idHint}"
else if root != null && !(safeId root) then
  throw "${rootPath}: ${idHint}"
else if root != null && !(builtins.hasAttr root elements) then
  throw "${rootPath}: missing root widget '${root}'; define ${widgetPath root} or correct the reference"
else if repeated != null then
  let
    first = builtins.head incoming.${repeated};
    second = builtins.elemAt incoming.${repeated} 1;
    problem = if first.parent == second.parent then "duplicate child" else "shared child";
  in
  throw "${edgePath second}: ${problem} '${repeated}', already referenced at ${edgePath first}; keep only one reference"
else if roots == [ ] then
  cycleError "no root: every widget is referenced" (builtins.head ids)
else if root != null && builtins.hasAttr root incoming then
  throw "${rootPath}: '${root}' is a child at ${
    edgePath (builtins.head incoming.${root})
  }; the root must have no parent. ${compose}"
else if builtins.length roots > 1 then
  let
    problem =
      if root == null then "cannot infer a root" else "not all widgets are reachable from root '${root}'";
  in
  throw "${widgetsPath}: ${problem}; multiple roots: ${lib.concatStringsSep ", " roots}. ${compose}"
else if builtins.length reached != count then
  let
    unreachable = builtins.removeAttrs elements (map (node: node.key) reached);
  in
  cycleError "cycle unreachable from root '${chosen}'" (
    builtins.head (builtins.attrNames unreachable)
  )
else
  chosen
