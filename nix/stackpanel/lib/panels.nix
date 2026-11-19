# Public lib.stackpanel.panels builders. The results are plain declarations for
# stackpanel.panels.<id> (or modules.<id>.actions.<actionId>), not a second UI
# schema. Panel options such as slot, nav, actions and order pass through.
{ lib }:
let
  sp = import ../db/lib/field.nix { inherit lib; };

  # Studio transports field values as strings. Keep strings verbatim and use
  # JSON for structured values and booleans (Nix's toString false is "").
  fieldValue =
    value:
    if value == null then
      null
    else if builtins.isBool value || builtins.isList value || builtins.isAttrs value then
      builtins.toJSON value
    else
      toString value;

  mkField =
    {
      name,
      value ? "",
      ...
    }@args:
    args
    // {
      inherit name;
      value = fieldValue value;
    };

  # A panel references an action by its registry key; never embed a command
  # line in panel metadata. The action itself takes validated JSON on stdin.
  mkAction =
    { script, ... }@args:
    args
    // {
      script = if lib.isDerivation script then lib.getExe script else script;
    };

  selectFields =
    {
      fields,
      include ? null,
      exclude ? [ "enable" ],
      ...
    }:
    lib.filterAttrs (
      name: field:
      !(builtins.elem name exclude)
      && (include == null || builtins.elem name include)
      && sp.isUiVisible field
    ) fields;

  # SpField resolves renderer type, options, labels and ordering at declaration
  # time. Use the same metadata for both module forms and app config panels.
  renderFields =
    fields: bind:
    let
      names = lib.sort (a: b: fields.${a}.ui.order < fields.${b}.ui.order) (lib.attrNames fields);
    in
    map (
      name:
      let
        field = fields.${name};
      in
      mkField (
        {
          inherit name;
          inherit (field.ui)
            type
            options
            label
            editable
            placeholder
            ;
          description = field.ui.description or field.description or null;
          example = fieldValue (field.ui.example or field.example or null);
        }
        // bind name field
      )
    ) names;

  # Forward the panel declaration; option evaluation supplies display defaults.
  panelAttrs = extra: args: removeAttrs args ([ "fields" "include" "exclude" ] ++ extra);

  joinPath = prefix: name: if prefix == "" then name else "${prefix}.${name}";
in
{
  inherit mkField mkAction;
  mkMarkdownField = args: mkField (args // { type = "FIELD_TYPE_MARKDOWN"; });
  # value is the variable/secret identifier; do not pass the secret contents.
  mkSecretRefField = args: mkField (args // { type = "FIELD_TYPE_SECRET_REF"; });
  mkStreamAction = args: mkAction (args // { outputMode = "stream"; });
  mkJsonAction = args: mkAction (args // { outputMode = "json"; });

  # Build an app config panel from SpFields, with camelCase edit paths relative
  # to apps.<app>. `apps` is already filtered by the caller to relevant apps.
  # Example: mkPanelFromSpFields { module = "go"; title = "Go";
  #   inherit (goSchema) fields; optionPrefix = "go"; apps = goApps; }
  mkPanelFromSpFields =
    { optionPrefix, apps, ... }@args:
    let
      fields = selectFields args;
      prefix = if optionPrefix == "" then [ ] else lib.splitString "." optionPrefix;
    in
    panelAttrs [ "optionPrefix" "apps" ] args
    // {
      type = "PANEL_TYPE_APP_CONFIG";
      fields = renderFields fields (name: _: { editPath = joinPath optionPrefix name; });
      apps = lib.mapAttrs (
        _: app:
        let
          values = lib.attrByPath prefix { } app;
        in
        {
          enabled = true;
          config = lib.mapAttrs (
            name: _:
            let
              value = values.${name} or null;
            in
            if value == null then "" else fieldValue value
          ) fields;
        }
      ) apps;
    };

  # Module-level analogue of mkPanelFromSpFields. Pass evaluated settings as
  # `values`; override configPath if the module uses a different mutation root.
  # Example: mkPanelFromModuleFields { module = "postgres"; title = "Database";
  #   inherit (schema) fields; values = cfg.settings; slot = "configuration"; }
  mkPanelFromModuleFields =
    {
      module,
      values,
      configPath ? "modules.${module}.settings",
      ...
    }@args:
    panelAttrs [ "values" "configPath" ] args
    // {
      type = "PANEL_TYPE_FORM";
      fields = renderFields (selectFields args) (
        name: field: {
          value = values.${name} or null;
          configPath = if field.ui.editable then joinPath configPath name else null;
        }
      );
    };
}
