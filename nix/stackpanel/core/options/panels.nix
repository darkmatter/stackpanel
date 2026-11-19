# ==============================================================================
# panels.nix
#
# Built-in and external modules contribute to the same Studio panel registry:
#
#   stackpanel.panels.go-status = {
#     module = "go";
#     title = "Go Environment";
#     slot = "overview";
#     spec = ./studio.json;
#   };
#
# The panels are exposed via nix eval for the agent/web UI to consume.
# ==============================================================================
{
  lib,
  config,
  options,
  ...
}:
let
  cfg = config.stackpanel;
  inherit (import ./modules/types.nix { inherit lib; }) relativeOptionPath;

  # ============================================================================
  # Type Definitions
  # ============================================================================

  # Panel types for UI rendering
  panelTypeEnum = lib.types.enum [
    "PANEL_TYPE_UNSPECIFIED"
    "PANEL_TYPE_STATUS"
    "PANEL_TYPE_APPS_GRID"
    "PANEL_TYPE_FORM"
    "PANEL_TYPE_TABLE"
    "PANEL_TYPE_CUSTOM"
    "PANEL_TYPE_APP_CONFIG"
    "PANEL_TYPE_TABS"
    "PANEL_TYPE_SPEC"
  ];

  # Field types for panel configuration
  fieldTypeEnum = lib.types.enum [
    "FIELD_TYPE_UNSPECIFIED"
    "FIELD_TYPE_STRING"
    "FIELD_TYPE_NUMBER"
    "FIELD_TYPE_BOOLEAN"
    "FIELD_TYPE_SELECT"
    "FIELD_TYPE_MULTISELECT"
    "FIELD_TYPE_APP_FILTER"
    "FIELD_TYPE_COLUMNS"
    "FIELD_TYPE_JSON"
    "FIELD_TYPE_CODE"
    "FIELD_TYPE_MARKDOWN"
    "FIELD_TYPE_SECRET_REF"
  ];

  # Panel field type
  panelFieldType = lib.types.submodule (
    { config, ... }: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Field name passed to the panel component as a prop key.";
          example = "metrics";
        };
        type = lib.mkOption {
          type = fieldTypeEnum;
          default = "FIELD_TYPE_STRING";
          description = ''
            Field renderer hint for the Studio UI.

            - `FIELD_TYPE_STRING`, `FIELD_TYPE_NUMBER`, `FIELD_TYPE_BOOLEAN`: scalar display/input values.
            - `FIELD_TYPE_SELECT`, `FIELD_TYPE_MULTISELECT`: selectable values from `options`.
            - `FIELD_TYPE_APP_FILTER`: app selector/filter control.
            - `FIELD_TYPE_COLUMNS`: table column metadata.
            - `FIELD_TYPE_JSON`: JSON-encoded structured data.
            - `FIELD_TYPE_CODE`: code or config text.
            - `FIELD_TYPE_MARKDOWN`: Markdown content.
            - `FIELD_TYPE_SECRET_REF`: a secret or variable reference, never its resolved value.
          '';
          example = "FIELD_TYPE_SELECT";
        };
        value = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "";
          description = ''
            Field value passed to the UI.

            Values are serialized as strings for transport. Use `builtins.toJSON`
            for arrays/objects consumed by JSON-aware panel renderers. `null`
            means unset.
          '';
          example = lib.literalExpression ''
            builtins.toJSON [
              { label = "PostgreSQL"; value = "running"; status = "ok"; }
              { label = "Redis"; value = "stopped"; status = "warning"; }
            ]
          '';
        };
        options = lib.mkOption {
          type = lib.types.listOf (
            lib.types.either lib.types.str (
              lib.types.submodule {
                options = {
                  value = lib.mkOption {
                    type = lib.types.str;
                    description = "Machine-readable option value submitted by the UI.";
                    example = "prod";
                  };
                  label = lib.mkOption {
                    type = lib.types.str;
                    description = "Human-readable label shown for this option in the UI.";
                    example = "Production";
                  };
                };
              }
            )
          );
          default = [ ];
          description = ''
            Selectable values for `FIELD_TYPE_SELECT` and `FIELD_TYPE_MULTISELECT` fields.

            Use strings when the display label and submitted value are identical,
            or `{ value, label }` objects when the UI label should differ from the
            persisted value.
          '';
          example = lib.literalExpression ''
            [
              "dev"
              "staging"
              { value = "prod"; label = "Production"; }
            ]
          '';
        };

        # Extended fields for PANEL_TYPE_APP_CONFIG
        label = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Human-readable field label; when null, the UI falls back to `name`.";
          example = "Database URL";
        };
        editable = lib.mkOption {
          type = lib.types.bool;
          default = config.configPath != null;
          defaultText = lib.literalExpression "config.configPath != null";
          description = "Whether Studio may submit edits. A field with a configPath is editable unless explicitly disabled.";
          example = true;
        };
        editPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Dot-separated path within the app's config for writes.
            E.g., "go.mainPackage" tells the agent to patch
            apps.<appId>.go.mainPackage in the data file.
          '';
        };
        placeholder = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Placeholder text shown in editable text input fields.";
          example = "postgres://localhost:5432/app";
        };
        configPath = lib.mkOption {
          type = lib.types.nullOr relativeOptionPath;
          default = null;
          description = "Dot-separated writable option path, relative to stackpanel.";
          example = "apps.web.port";
        };
        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Help text shown below the field in the Studio UI.";
          example = "Used by local development and preview deploys.";
        };
        example = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Example value shown as inline help for this field.";
          example = "3000";
        };
      };
    }
  );

  # Bundle capabilities are opt-in. Only a derivation may supply the asset root;
  # consumers get its output path, not arbitrary filesystem or remote URLs.
  uiBundleType = lib.types.submodule {
    options = {
      package = lib.mkOption {
        type = lib.types.addCheck lib.types.package lib.isDerivation;
        description = "Derivation whose output directory contains the static UI assets.";
      };
      entry = lib.mkOption {
        type = lib.types.addCheck lib.types.str (
          entry:
          lib.all (
            part:
            !(builtins.elem part [
              ""
              "."
              ".."
            ])
          ) (lib.splitString "/" entry)
        );
        default = "index.html";
        description = "Entry file relative to the package output directory.";
      };
      permissions = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "config:read"
            "config:patch"
            "actions:run"
            "service:proxy"
          ]
        );
        default = [ ];
        description = "Host capabilities requested by this panel, scoped to its owning module.";
      };
      actionIds = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.nonEmptyStr);
        default = null;
        description = ''
          Restrict the `actions:run` grant to these action IDs on the owning
          module. Null allows all of that module's actions; an empty list
          allows none. This option never grants `actions:run` on its own.
        '';
      };
    };
  };

  navType = lib.types.submodule {
    options = {
      section = lib.mkOption {
        type = lib.types.enum [
          "Core"
          "Workspace"
          "Cloud"
          "Extensions"
        ];
        default = "Extensions";
        description = "Sidebar section for a navigation entry.";
      };
      label = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional sidebar label overriding the panel title.";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional Lucide icon override for the navigation entry.";
      };
    };
  };

  idListOption =
    description:
    lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      inherit description;
    };

  # A panel belonging to a registered module.
  modulePanelType = lib.types.submodule (
    { config, name, ... }: {
      options = {
        # Which module this panel belongs to
        module = lib.mkOption {
          type = lib.types.str;
          description = ''
            The owning module ID (e.g., "go", "caddy", "healthchecks").
            Used for grouping panels in the UI.
          '';
          example = "healthchecks";
        };

        # Display settings
        title = lib.mkOption {
          type = lib.types.str;
          description = "Title shown at the top of the panel.";
          example = "Go Environment";
        };
        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional summary shown below the panel title.";
          example = "Healthcheck status for configured services.";
        };
        readme = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Module documentation in markdown format.
            Rendered in the UI panel to help users understand the module's configuration.
          '';
          example = lib.literalExpression ''
            "## Healthchecks\n\nCritical failures mark the module unhealthy. Warning failures mark it degraded."
          '';
        };
        icon = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Icon name from lucide-react, without the React component suffix.";
          example = "activity";
        };

        # Panel type and configuration
        type = lib.mkOption {
          type = panelTypeEnum;
          default = if config.spec != null then "PANEL_TYPE_SPEC" else "PANEL_TYPE_STATUS";
          defaultText = lib.literalMD "`PANEL_TYPE_SPEC` with `spec`, otherwise `PANEL_TYPE_STATUS`";
          apply =
            type:
            if config.spec != null && config.uiBundle != null then
              throw "stackpanel.panels.${name}: `spec` and `uiBundle` are mutually exclusive"
            else if config.spec != null && type != "PANEL_TYPE_SPEC" then
              throw "stackpanel.panels.${name}: `spec` conflicts with type `${type}`; omit `type` or use `PANEL_TYPE_SPEC`"
            else if type == "PANEL_TYPE_SPEC" && config.spec == null then
              throw "stackpanel.panels.${name}: `PANEL_TYPE_SPEC` requires a `spec` document"
            else
              type;
          description = ''
            Panel renderer used by the Studio UI.

            - `PANEL_TYPE_STATUS`: status/metric summary cards.
            - `PANEL_TYPE_APPS_GRID`: app cards keyed by `apps`.
            - `PANEL_TYPE_FORM`: editable or read-only fields.
            - `PANEL_TYPE_TABLE`: tabular data from `columns` and `rows`.
            - `PANEL_TYPE_APP_CONFIG`: app configuration editor fields.
            - `PANEL_TYPE_TABS`: an ordered group of panels referenced by `tabs`.
            - `PANEL_TYPE_CUSTOM`: sandboxed static UI defined by `uiBundle`.
            - `PANEL_TYPE_SPEC`: native Studio UI defined by `spec` (inferred).
          '';
          example = "PANEL_TYPE_TABLE";
        };
        slot = lib.mkOption {
          type = lib.types.enum [
            "module"
            "sidebar"
            "overview"
            "configuration"
            "app:runtime"
            "app:framework"
            "app:container"
            "app:deployment"
            "app:tab"
            "setup"
          ];
          default = "module";
          description = "Studio surface where this panel is mounted.";
        };
        nav = lib.mkOption {
          type = navType;
          default = { };
          description = "Navigation metadata for the sidebar slot.";
        };
        actions = idListOption "Ordered IDs of actions on the owning module to show in the panel header.";
        rowActions = idListOption "Ordered IDs of module actions available for each table row.";
        tabs = idListOption "Ordered panel registry IDs displayed inside a tabs panel.";
        dataAction = lib.mkOption {
          type = lib.types.nullOr lib.types.nonEmptyStr;
          default = null;
          description = "Module action with JSON output providing live status or table data.";
        };
        spec = (import ../../lib/ui { inherit lib; }).specOption;
        uiBundle = lib.mkOption {
          type = lib.types.nullOr uiBundleType;
          default = null;
          description = "Static UI package and requested permissions for a custom panel.";
        };
        order = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Display order within the module; lower values render first.";
          example = 10;
        };
        fields = lib.mkOption {
          type = lib.types.listOf panelFieldType;
          default = [ ];
          description = ''
            Field definitions passed to the panel renderer.

            For status panels, fields often carry JSON-encoded metric arrays. For
            form and app-config panels, fields describe editable inputs and their
            `configPath`/`editPath` targets.
          '';
          example = lib.literalExpression ''
            [
              {
                name = "environment";
                label = "Environment";
                type = "FIELD_TYPE_SELECT";
                value = "dev";
                options = [ "dev" "staging" "prod" ];
                editable = true;
                configPath = "apps.web.env";
              }
            ]
          '';
        };

        # Visibility
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this panel is included in computed UI output.";
          example = false;
        };

        # Optional: Columns for PANEL_TYPE_TABLE
        columns = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                key = lib.mkOption {
                  type = lib.types.str;
                  description = "Column key used to read values from each row object.";
                  example = "status";
                };
                label = lib.mkOption {
                  type = lib.types.str;
                  description = "Human-readable column header shown in table panels.";
                  example = "Status";
                };
              };
            }
          );
          default = [ ];
          description = "Column definitions used by `PANEL_TYPE_TABLE`; each `key` must match keys present in `rows`.";
          example = lib.literalExpression ''
            [
              { key = "name"; label = "Service"; }
              { key = "status"; label = "Status"; }
            ]
          '';
        };

        # Optional: Rows for PANEL_TYPE_TABLE
        rows = lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.str);
          default = [ ];
          description = "Rows rendered by `PANEL_TYPE_TABLE`, with string values keyed by `columns[*].key`.";
          example = lib.literalExpression ''
            [
              { name = "postgres"; status = "ok"; port = "5432"; }
              { name = "redis"; status = "warning"; port = "6379"; }
            ]
          '';
        };

        # Optional: Apps data for PANEL_TYPE_APPS_GRID
        apps = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                enabled = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Whether this app entry is visible in the apps-grid panel.";
                  example = true;
                };
                config = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "String metadata for this app entry, consumed by the apps-grid panel.";
                  example = {
                    port = "3000";
                    url = "http://localhost:3000";
                  };
                };
              };
            }
          );
          default = { };
          description = ''
            Per-app metadata rendered by `PANEL_TYPE_APPS_GRID` panels.

            Attribute names are app IDs. `config` values are strings so the
            serialized panel output remains JSON-friendly and predictable.
          '';
          example = lib.literalExpression ''
            {
              web = {
                enabled = true;
                config = {
                  port = "3000";
                  url = "http://localhost:3000";
                  framework = "tanstack-start";
                };
              };
            }
          '';
        };
      };
    }
  );

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Writable settings are a projection of the evaluated module namespace, not
  # the (string-valued) display data in panel.apps. Reject an entire requested
  # field if any part isn't portable JSON; stripping only its unsafe children
  # would let a patch silently replace data the panel never saw.
  publicKey =
    key:
    !(lib.hasPrefix "_" key)
    && !(builtins.elem key [
      "constructor"
      "prototype"
      "env"
      "envs"
      "environments"
      "variables"
      "secrets"
    ]);
  plainRecord =
    v:
    builtins.isAttrs v
    && !(v ? outPath || v ? __toString || v ? __functor || v ? _type || lib.isDerivation v);
  portable =
    v:
    if builtins.isAttrs v then
      plainRecord v && lib.all (key: publicKey key && portable v.${key}) (builtins.attrNames v)
    else if builtins.isList v then
      lib.all portable v
    else if builtins.isString v then
      !(builtins.hasContext v || lib.hasPrefix "${builtins.storeDir}/" v)
    else if builtins.isInt v then
      v >= -9007199254740991 && v <= 9007199254740991
    else if builtins.isFloat v then
      builtins.toJSON v != "null"
    else
      builtins.elem (builtins.typeOf v) [
        "bool"
        "null"
      ];
  # Capture options inside each concrete app's module evaluation. Generic
  # getSubOptions would lose declarations conditional on the app name.
  appSchemaModule = { options, ... }: {
    options._panelFieldSchemas = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      internal = true;
      description = "Project writable field types from this app's effective option declarations.";
      default =
        owner: keys:
        let
          scope = options.${owner} or { };
          schema = (import ../../lib/json-schema.nix { inherit lib; }).writableSchema;
        in
        if lib.isOption scope then
          { }
        else
          lib.filterAttrs (_: s: s != null) (lib.mapAttrs (_: schema) (builtins.intersectAttrs keys scope));
    };
  };
  writableApps =
    panel:
    lib.filterAttrs (_: fields: fields != { }) (
      lib.mapAttrs (
        appId: entry:
        let
          scope = cfg.apps.${appId}.${panel.module} or { };
          requested = lib.filterAttrs (key: _: publicKey key) entry.config;
          schemas = (cfg.apps.${appId}._panelFieldSchemas or (_: _: { })) panel.module requested;
        in
        if
          !entry.enabled
          || requested == { }
          || !(publicKey panel.module)
          || !(builtins.isAttrs scope)
          || scope ? outPath
          || scope ? __toString
          || scope ? __functor
          || scope ? _type
        then
          { }
        else
          lib.mapAttrs
            (key: value: {
              inherit value;
              schema = schemas.${key};
            })
            (
              lib.filterAttrs (
                _: v:
                let
                  result = builtins.tryEval (portable v);
                in
                result.success && result.value
              ) (builtins.intersectAttrs schemas scope)
            )
      ) panel.apps
    );

  # Serialize a panel for JSON output
  serializePanel = id: panel: {
    inherit id;
    inherit (panel) module;
    inherit (panel) title;
    inherit (panel) description;
    inherit (panel) readme;
    inherit (panel) icon;
    inherit (panel) type;
    inherit (panel) order;
    inherit (panel) enabled;
    inherit (panel)
      slot
      spec
      actions
      rowActions
      tabs
      dataAction
      ;
    nav = lib.filterAttrs (_: v: v != null) {
      inherit (panel.nav) section label icon;
    };
    uiBundle =
      if panel.uiBundle == null then
        null
      else
        {
          inherit (panel.uiBundle) entry permissions actionIds;
          package = toString panel.uiBundle.package;
          # Used by the agent to realize this evaluated package on first open.
          drvPath = toString panel.uiBundle.package.drvPath;
        }
        //
          lib.optionalAttrs
            (panel.type == "PANEL_TYPE_CUSTOM" && builtins.elem "config:patch" panel.uiBundle.permissions)
            (
              let
                apps = writableApps panel;
              in
              {
                appSettings = lib.mapAttrs (_: lib.mapAttrs (_: field: field.value)) apps;
                appSchemas = lib.mapAttrs (_: fields: {
                  type = "object";
                  additionalProperties = false;
                  properties = lib.mapAttrs (_: field: field.schema) fields;
                }) apps;
              }
            );
    fields = map (f: {
      inherit (f) name;
      inherit (f) type;
      inherit (f) value;
      inherit (f) options;
      inherit (f) label;
      inherit (f) editable;
      inherit (f) editPath;
      inherit (f) placeholder;
      inherit (f) configPath;
      inherit (f) description;
      inherit (f) example;
    }) panel.fields;
    apps = lib.mapAttrs (_name: appData: {
      inherit (appData) enabled;
      inherit (appData) config;
    }) panel.apps;
    inherit (panel) columns;
    inherit (panel) rows;
  };

in
{
  # ============================================================================
  # Options
  # ============================================================================

  options.stackpanel.panels = lib.mkOption {
    type = lib.types.attrsOf modulePanelType;
    default = { };
    description = ''
      Studio panels for built-in and external modules. Each panel describes
      module state, configuration, or managed resources and is mounted in `slot`.
    '';
    example = lib.literalExpression ''
      {
        go-status = {
          module = "go";
          title = "Go Environment";
          slot = "overview";
          spec = ./studio.json;
        };
        caddy-status = {
          module = "caddy";
          title = "Reverse Proxy";
          type = "PANEL_TYPE_STATUS";
          order = 20;
          fields = [ ... ];
        };
      }
    '';
  };

  # Keyed metadata for SDK validation and other Nix consumers.
  options.stackpanel.panelsComputed = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    internal = true;
    description = "Enabled panel descriptors indexed by ID for Nix consumers.";
  };

  # List of panels (for iteration)
  options.stackpanel.panelsList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    description = "List of enabled panels sorted by display order for UI iteration.";
  };

  # ============================================================================
  # Config
  # ============================================================================

  config = lib.mkMerge [
    {
      # Serialize panels for UI
      stackpanel.panelsComputed = lib.mapAttrs serializePanel (
        lib.filterAttrs (_id: p: p.enabled) cfg.panels
      );

      # Sorted list of panels
      stackpanel.panelsList = lib.sort (a: b: a.order < b.order) (lib.attrValues cfg.panelsComputed);
    }
    (lib.optionalAttrs (options.stackpanel ? appModules) {
      stackpanel.appModules = [ appSchemaModule ];
    })
  ];
}
