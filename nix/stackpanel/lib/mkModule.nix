# Module factories for lib.stackpanel. Settings and per-app declarations may
# mix SpFields, lib.mkOption declarations, and { type, default?, ... } leaves.
{ lib }:
let
  spField = import ../db/lib/field.nix { inherit lib; };
  inherit (import ./json-schema.nix { inherit lib; }) jsonSchemaFromSpFields;

  toOptions = lib.mapAttrs (
    _: value:
    if value._isSpField or false then
      spField.asOption value
    else if lib.isOption value then
      value
    else if (value.type._type or null) == "option-type" then
      lib.mkOption value
    else
      toOptions value
  );

  # Apply a structural edit without evaluating mkIf predicates, discarding
  # merge priorities, or touching any values removed by the edit.
  mapDefinition =
    f: def:
    let
      kind = def._type or null;
    in
    if kind == "merge" then
      lib.mkMerge (map (mapDefinition f) def.contents)
    else if kind == "if" || kind == "override" || kind == "order" then
      def // { content = mapDefinition f def.content; }
    else
      f def;

  globalPanels = mapDefinition (
    lib.mapAttrs (_: mapDefinition (panel: removeAttrs panel [ "uiBundle" ]))
  );
  globalConfig = mapDefinition (
    root:
    root
    // lib.optionalAttrs (root ? stackpanel) {
      stackpanel = mapDefinition (
        sp:
        removeAttrs sp [
          "devshell"
          "scripts"
          "modulePackages"
          "packages"
          "outputs"
          "appBuildProviders"
          "flakeApps"
        ]
        // lib.optionalAttrs (sp ? panels) { panels = globalPanels sp.panels; }
      ) root.stackpanel;
    }
  );

  mkModule =
    {
      name,
      meta,
      features ? { },
      source ? {
        type = "local";
      },
      settings ? { },
      appModule ? null,
      appOptions ? { },
      defaultEnable ? false,
      enablePath ? "modules.${name}.enable",
      configPath ? "modules.${name}.settings",
      requires ? [ ],
      conflicts ? [ ],
      priority ? 100,
      tags ? [ ],
      flakeInputs ? [ ],
      configSchema ? null,
      readme ? null,
      healthcheckModule ? null,
      actions ? { },
      panels ? { },
      ui ? null,
      packages ? [ ],
      adoption ? null,
      config ? _: { },
    }@spec:
    args:
    let
      id = name;
      sp = args.config.stackpanel;
      cfg = sp.modules.${id};
      isGlobal = args.isGlobalEval or false;
      resolve = value: if builtins.isFunction value then value cfg else value;
      hasAppOptions = appOptions != { };
      behavior = config cfg;
      explicitPanels = resolve panels;
      uiId = "${id}-ui";
      modulePanels =
        if ui == null then
          explicitPanels
        else if builtins.hasAttr uiId explicitPanels then
          throw "mkModule `${id}`: `ui` and `panels.${uiId}` declare the same panel; choose one or rename the explicit panel"
        else
          explicitPanels
          // {
            ${uiId} = {
              title = cfg.meta.name;
              slot = "module";
              spec = ui;
            };
          };
      ownedPanels = lib.mapAttrs (_: mapDefinition (p: p // { module = id; })) modulePanels;
    in
    {
      # Extend the *shared* typed registry; never redeclare modules.<id> as
      # an ad-hoc option (doing so loses defaults for meta, source, actions...).
      options = lib.optionalAttrs (settings != { }) {
        stackpanel.modules = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, ... }: {
                # Name is a submodule argument (itself provided by config).
                # Don't force it while collecting outer option declarations.
                options.settings = lib.mkOption {
                  type = lib.types.submodule { options = lib.optionalAttrs (name == id) (toOptions settings); };
                };
              }
            )
          );
        };
      };
      config = lib.mkMerge [
        {
          stackpanel.modules.${id} = {
            enable = lib.mkDefault (
              if enablePath == "modules.${id}.enable" then
                defaultEnable
              else
                lib.getAttrFromPath (lib.splitString "." enablePath) sp
            );
            inherit
              meta
              source
              requires
              conflicts
              priority
              tags
              healthcheckModule
              flakeInputs
              enablePath
              configPath
              ;
            features =
              lib.optionalAttrs (spec ? packages) { packages = true; }
              // features
              // lib.optionalAttrs (hasAppOptions || appModule != null) { appModule = true; };
            actions = resolve actions;
            readme = if builtins.isPath readme then builtins.readFile readme else readme;
            configSchema =
              if configSchema != null then
                (if builtins.isString configSchema then configSchema else builtins.toJSON configSchema)
              else if settings != { } then
                jsonSchemaFromSpFields settings
              else
                null;
          };
        }
        (lib.optionalAttrs (adoption != null) {
          stackpanel.addons.${id} = adoption // {
            module = id;
          };
        })
        (lib.optionalAttrs (hasAppOptions || appModule != null) {
          stackpanel.appModules =
            lib.optional (appModule != null) appModule
            ++ lib.optional hasAppOptions { options = toOptions appOptions; };
        })
        (lib.mkIf cfg.enable (if isGlobal then globalConfig behavior else behavior))
        (lib.optionalAttrs (spec ? panels || spec ? ui) (
          lib.mkIf cfg.enable {
            stackpanel.panels = if isGlobal then globalPanels ownedPanels else ownedPanels;
          }
        ))
        (lib.optionalAttrs (!isGlobal && spec ? packages) (
          lib.mkIf cfg.enable {
            stackpanel.modulePackages.${id} = resolve packages;
          }
        ))
      ];
    };
in
{
  inherit mkModule;
  mkSimpleModule =
    {
      name,
      displayName,
      description ? null,
      category ? "development",
      icon ? null,
      config,
    }:
    mkModule {
      inherit name config;
      meta = {
        name = displayName;
        inherit description category icon;
      };
    };
}
