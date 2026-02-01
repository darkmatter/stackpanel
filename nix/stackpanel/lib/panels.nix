# ==============================================================================
# nix/stackpanel/lib/panels.nix
#
# Panel generation library for auto-generating UI panels from SpField definitions.
#
# Instead of hand-writing panel field lists in each module's ui.nix, this library
# reads the SpField metadata (from go.proto.nix, bun.proto.nix, etc.) and
# automatically produces PANEL_TYPE_APP_CONFIG panel definitions.
#
# Usage:
#   let
#     panelsLib = import ./panels.nix { inherit lib; };
#     goSchema = import ../db/schemas/go.proto.nix { inherit lib; };
#   in
#   panelsLib.mkPanelFromSpFields {
#     module = "go";
#     title = "Go Configuration";
#     icon = "code";
#     fields = goSchema.fields;
#     optionPrefix = "go";
#     apps = goApps;   # evaluated apps (filtered to Go-enabled)
#     exclude = [ "enable" ];
#   }
# ==============================================================================
{ lib }:
let
  sp = import ../db/lib/field.nix { inherit lib; };

  # Navigate a nested attrset by a dot-separated path string
  # e.g., getByPath app "linting.oxlint" → app.linting.oxlint
  getByPath =
    attrset: path:
    let
      parts = lib.splitString "." path;
    in
    lib.foldl' (acc: key: acc.${key} or null) attrset parts;
in
{
  # ===========================================================================
  # mkPanelFromSpFields
  #
  # Auto-generate a PANEL_TYPE_APP_CONFIG panel from SpField definitions.
  #
  # Arguments:
  #   module       - Module identifier (e.g., "go", "bun")
  #   title        - Display title for the panel
  #   icon         - Lucide icon name (optional)
  #   fields       - Attrset of SpField definitions (from *.proto.nix)
  #   optionPrefix - Key in the app submodule (e.g., "go" for app.go.*)
  #   apps         - Evaluated app configs (pre-filtered to relevant apps)
  #   exclude      - Field names to exclude (default: ["enable"])
  #   include      - If set, only include these field names (whitelist)
  #   order        - Panel display order (default: 100)
  #   readme       - Module documentation in markdown (optional, shown in UI)
  #
  # Returns:
  #   A panel definition suitable for stackpanel.panels.<id>
  #
  # ===========================================================================
  mkPanelFromSpFields =
    {
      module,
      title,
      icon ? null,
      fields,
      optionPrefix,
      apps,
      exclude ? [ "enable" ],
      include ? null,
      order ? 100,
      readme ? null,
    }:
    let
      # Filter to UI-visible fields, applying include/exclude
      visibleFields = lib.filterAttrs (
        name: field:
        let
          isSpField = field._isSpField or false;
          hasUi = isSpField && field.ui != null && !(field.ui.hidden or false);
          included = if include != null then builtins.elem name include else true;
          excluded = builtins.elem name exclude;
        in
        hasUi && included && !excluded
      ) fields;

      # Convert SpField definitions to panel field entries
      # Include _order for sorting, then strip it before output
      panelFields = lib.mapAttrsToList (name: field: {
        inherit name;
        type = field.ui.type;
        value = ""; # Per-app values go in the apps map, not here
        options = field.ui.options;
        label = field.ui.label;
        editable = field.ui.editable;
        editPath = "${optionPrefix}.${name}";
        placeholder = field.ui.placeholder;
        # Help text from field description
        description = field.ui.description or field.description or null;
        # Example value for additional context (JSON-encoded if complex)
        example =
          let
            ex = field.ui.example or field.example or null;
          in
          if ex == null then
            null
          else if builtins.isString ex then
            ex
          else
            builtins.toJSON ex;
        _order = field.ui.order;
      }) visibleFields;

      # Sort fields by their UI order, then strip the internal _order key
      sortedFields = lib.sort (a: b: a._order < b._order) panelFields;
      cleanFields = map (f: removeAttrs f [ "_order" ]) sortedFields;

      # Serialize a Nix value to a string for the config map
      valueToString =
        val:
        if val == null then
          ""
        else if builtins.isBool val then
          builtins.toJSON val
        else if builtins.isList val then
          builtins.toJSON val
        else if builtins.isAttrs val then
          builtins.toJSON val
        else if builtins.isInt val || builtins.isFloat val then
          toString val
        else
          toString val;

      # Generate per-app config from evaluated values
      # Supports both simple ("go") and nested ("linting.oxlint") option prefixes
      appsData = lib.mapAttrs (
        appName: app:
        let
          prefixVal = getByPath app optionPrefix;
        in
        {
          enabled = true;
          config = lib.mapAttrs (
            fieldName: _field:
            let
              val = if prefixVal != null then prefixVal.${fieldName} or null else null;
            in
            valueToString val
          ) visibleFields;
        }
      ) apps;

    in
    {
      inherit
        module
        title
        icon
        order
        readme
        ;
      type = "PANEL_TYPE_APP_CONFIG";
      enabled = true;
      fields = cleanFields;
      apps = appsData;
    };
}
