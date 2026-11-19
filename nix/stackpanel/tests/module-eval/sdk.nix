# Exercise the public contract against the real registry and panel types.
{ lib, pkgs }:
let
  sdk = import ../../lib/sdk.nix { inherit lib; };
  moduleLib = lib // {
    stackpanel = sdk;
  };
  check = name: actual: expected: {
    name = "SDK: ${name}";
    inherit actual expected;
  };
  option = type: default: lib.mkOption { inherit type default; };
  sampleUi = {
    root = "message";
    elements.message = {
      type = "Text";
      props.content = "Sample";
    };
  };
  metadataModule =
    { lib, ... }:
    lib.stackpanel.mkModule {
      name = "sample";
      meta = {
        name = "Sample";
        category = "custom-testing";
      };
      readme = "# Sample";
      flakeInputs = [
        {
          name = "dep";
          url = "github:org/dep";
        }
      ];
      settings = {
        endpoint.port = {
          type = lib.types.port;
          default = 8080;
        };
        tags = lib.stackpanel.spField.string {
          index = 1;
          repeated = true;
        };
        tool = lib.mkOption {
          type = lib.types.package;
          default = throw "global package forced";
        };
      };
      appOptions.sample.mode = lib.mkOption {
        type = lib.types.enum [
          "dev"
          "ci"
        ];
        default = "dev";
      };
      actions.inspect.script = "sample-inspect";
      ui = sampleUi;
      panels.sample = {
        title = "Sample";
        uiBundle = throw "global UI bundle forced";
      };
      packages = throw "global modulePackages forced";
      config =
        _:
        lib.mkMerge [
          { stackpanel.devshell = throw "global devshell forced"; }
          (lib.mkIf true { stackpanel.scripts = throw "global scripts forced"; })
          { stackpanel.nixosModules.sample = { }; }
        ];
    };
  evaluate =
    isGlobalEval: modules:
    (lib.evalModules {
      inherit modules;
      specialArgs = {
        lib = moduleLib;
        inherit isGlobalEval;
        inputs = { };
      };
    }).config.stackpanel;
  registry = [
    ../../core/options/modules.nix
    ../../core/options/panels.nix
    {
      options.stackpanel = {
        enable = option lib.types.bool true;
        devshell = option lib.types.attrs { };
        scripts = option lib.types.attrs { };
        nixosModules = option (lib.types.attrsOf lib.types.deferredModule) { };
        modulePackages = option (lib.types.attrsOf (lib.types.listOf lib.types.package)) { };
        appModules = option (lib.types.listOf lib.types.deferredModule) [ ];
      };
    }
  ];
  candidates = [
    (sdk.normalizeModule metadataModule)
    (sdk.mkSimpleModule {
      name = "other";
      displayName = "Other";
      config = _: { };
    })
  ];
  disabled = evaluate false (registry ++ candidates);
  metadata = disabled.modulesComputedAll.sample;
  schema = builtins.fromJSON metadata.configSchema;
  global = evaluate true (
    registry
    ++ candidates
    ++ [
      {
        stackpanel.modules.sample.enable = true;
        stackpanel.panels.sample-ui.order = 10;
        stackpanel.panels.hidden = {
          module = "sample";
          title = "Hidden";
          enabled = false;
        };
      }
    ]
  );
  serializer = import ../../lib/serialize.nix { inherit lib; };
  descriptorView =
    project:
    let
      state = builtins.fromJSON (builtins.toJSON (project global));
    in
    {
      keys = lib.filter (k: builtins.match "(modules.*|panels.*|panelModules|ui)" k != null) (
        builtins.attrNames state
      );
      modules = map (m: { inherit (m) id enabled; }) state.modulesListAll;
      panels = map (p: p.id) state.panelsList;
    };
  expectedView = {
    keys = [ "modulesListAll" "panelsList" ];
    modules = [
      { id = "other"; enabled = false; }
      { id = "sample"; enabled = true; }
    ];
    panels = [ "sample-ui" "sample" ];
  };
  acceptsPanels =
    modules:
    let
      sp = evaluate false (registry ++ modules);
    in
    (builtins.tryEval (builtins.deepSeq sp.panelsComputed true)).success;
  specPanel = {
    module = "sample";
    title = "Spec";
    spec = sampleUi;
  };
  writablePanel = {
    title = "Scoped settings";
    module = "sample";
    type = "PANEL_TYPE_CUSTOM";
    uiBundle = {
      package = pkgs.hello;
      permissions = [ "config:patch" ];
    };
    apps = {
      web.config = lib.genAttrs [
        "mode"
        "flags"
        "selection"
        "untyped"
        "missing"
        "tool"
        "context"
        "nestedTool"
        "env"
      ] (_: "display only");
      worker.config.mode = "wrong type and value";
      off = {
        enabled = false;
        config.mode = "disabled";
      };
      other.config.unrelated = "wrong namespace";
      empty.config = { };
    };
  };
  scopedFixture =
    selectionType: selection:
    evaluate false [
      ../../core/options/panels.nix
      ({ config, ... }: {
        options.stackpanel.appModules = option (lib.types.listOf lib.types.deferredModule) [ ];
        options.stackpanel.apps = option (lib.types.attrsOf (
          lib.types.submoduleWith {
            modules = config.stackpanel.appModules;
          }
        )) { };
        config.stackpanel = {
          appModules = [
            ({ name, ... }: {
              options = {
                sample = {
                  mode = option (if name == "web" then lib.types.bool else lib.types.int) (
                    throw "schema forced default"
                  );
                  selection = option selectionType (throw "schema forced default");
                  flags.count = lib.mkOption { type = lib.types.int; };
                  flags.options = lib.mkOption { type = lib.types.listOf (lib.types.nullOr lib.types.str); };
                  tool = lib.mkOption { type = lib.types.package; };
                  context = lib.mkOption { type = lib.types.str; };
                  nestedTool = lib.mkOption { type = lib.types.listOf lib.types.path; };
                  untyped = lib.mkOption { type = lib.types.raw; };
                  env = lib.mkOption { type = lib.types.raw; };
                  hidden = lib.mkOption { type = lib.types.raw; };
                };
                other = lib.mkOption { type = lib.types.raw; };
                unrelated = lib.mkOption { type = lib.types.raw; };
              };
            })
          ];
          apps = {
            web.sample = {
              mode = false;
              inherit selection;
              untyped = abort "opaque grant forced";
              flags = {
                count = 2;
                options = [
                  "A"
                  null
                ];
              };
              tool = pkgs.hello;
              context = "${pkgs.hello}/bin/hello";
              nestedTool = [ ./. ];
              env = abort "private environment forced";
              hidden = abort "undeclared field forced";
            };
            worker = {
              sample.mode = 3;
              other.mode = abort "wrong namespace forced";
            };
            off.unrelated = abort "disabled app forced";
            empty.unrelated = abort "empty grant forced";
            other.unrelated = abort "other namespace forced";
          };
          panels = {
            writable = writablePanel;
            readonly = writablePanel // {
              uiBundle = writablePanel.uiBundle // {
                permissions = [ "config:read" ];
              };
            };
            table = writablePanel // {
              type = "PANEL_TYPE_TABLE";
            };
          };
        };
      })
    ];
  scopedPanels = scopedFixture (lib.types.listOf lib.types.str) [ ];
  webSchema = scope: scope.panelsComputed.writable.uiBundle.appSchemas.web;
in
[
  (check "public module state exposes all modules and ordered, enabled panels once"
    (descriptorView serializer.projectState) expectedView)
  (check "trusted editor config uses the same module and panel views"
    (descriptorView serializer.projectConfig) expectedView)
  (check "mkModule rejects non-display metadata nested in meta"
    (builtins.tryEval (
      builtins.deepSeq (evaluate false (registry ++ [
        (sdk.mkModule { name = "misplaced"; meta.requires = [ "other" ]; })
      ])).modulesListAll true
    )).success
    false
  )
  (check "form field writes require stackpanel-relative paths" (acceptsPanels [
    {
      stackpanel.panels.form = {
        module = "sample";
        title = "Settings";
        fields = [{ name = "port"; configPath = "stackpanel.modules.sample.settings.port"; }];
      };
    }
  ]) false)
  (check "custom app patch grants use only declared, portable fields in the owning namespace"
    (builtins.fromJSON (builtins.toJSON scopedPanels.panelsComputed.writable.uiBundle.appSettings))
    {
      web = {
        mode = false;
        flags = {
          count = 2;
          options = [
            "A"
            null
          ];
        };
        selection = [ ];
      };
      worker.mode = 3;
    }
  )
  (check
    "app grants carry declaration types, not display strings, default values or inferred list contents"
    (map (fixture: (webSchema fixture).properties.selection) [
      (scopedFixture lib.types.str "single")
      scopedPanels
      (scopedFixture (lib.types.listOf lib.types.int) [ ])
    ])
    [
      { type = "string"; }
      {
        type = "array";
        items.type = "string";
      }
      {
        type = "array";
        items.type = "integer";
      }
    ]
  )
  (check
    "app grant schema is stable across value-only changes, field sets match, app declarations stay local"
    [
      (
        (webSchema scopedPanels) == webSchema (scopedFixture (lib.types.listOf lib.types.str) [ "changed" ])
      )
      (
        (builtins.attrNames (webSchema scopedPanels).properties)
        == builtins.attrNames scopedPanels.panelsComputed.writable.uiBundle.appSettings.web
      )
      (webSchema scopedPanels).properties.mode
      scopedPanels.panelsComputed.writable.uiBundle.appSchemas.worker.properties.mode
    ]
    [
      true
      true
      { type = "boolean"; }
      { type = "integer"; }
    ]
  )
  (check "other panel projections do not expose app patch settings"
    (map (id: scopedPanels.panelsComputed.${id}.uiBundle ? appSettings) [
      "readonly"
      "table"
    ])
    [
      false
      false
    ]
  )
  (check "plan example registers disabled metadata"
    [
      metadata.enabled
      metadata.enablePath
      metadata.configPath
      metadata.readme
      metadata.meta.category
      metadata.actions.inspect.outputMode
      metadata.features.appModule
      (builtins.head metadata.missingFlakeInputs).name
      (metadata ? panels)
      (disabled.panels ? sample)
      (disabled.panels ? sample-ui)
    ]
    [
      false
      "modules.sample.enable"
      "modules.sample.settings"
      "# Sample"
      "custom-testing"
      "stream"
      true
      "dep"
      false
      false
      false
    ]
  )
  (check "runtime schema from mixed SpFields and Nix declarations"
    [
      schema.properties.endpoint.properties.port.default
      schema.properties.tags.type
      (schema.properties.tool ? default)
    ]
    [ 8080 "array" false ]
  )
  (check "settings, metadata defaults and per-app declarations coexist"
    [
      metadata.settings.endpoint.port
      metadata.actions.inspect.argsSchema.type
      (builtins.attrNames disabled.modules.other.settings)
      (lib.evalModules { modules = disabled.appModules; }).config.sample.mode
    ]
    [
      8080
      "object"
      [ ]
      "dev"
    ]
  )
  (check "global evaluation keeps NixOS outputs and never forces local packages"
    [
      (global.nixosModules ? sample)
      global.devshell
      global.scripts
      global.modulePackages
      global.panels.sample.module
      global.panels.sample.uiBundle
      global.panelsComputed.sample-ui.spec.elements.message.props.content
    ]
    [
      true
      { }
      { }
      { }
      "sample"
      null
      "Sample"
    ]
  )
  (check "native spec cannot select another renderer, share a bundle, or omit its document"
    (map (panel: acceptsPanels [ { stackpanel.panels.invalid = panel; } ]) [
      (specPanel // { type = "PANEL_TYPE_STATUS"; })
      (specPanel // { uiBundle.package = pkgs.hello; })
      (
        specPanel
        // {
          type = "PANEL_TYPE_SPEC";
          spec = null;
        }
      )
    ])
    [
      false
      false
      false
    ]
  )
  (check "spec rejects nested Nix paths rather than coercing them to store strings" (acceptsPanels [
    {
      stackpanel.panels.invalid = specPanel // {
        spec.state.data.file = ./.;
      };
    }
  ]) false)
  (check "ui refuses to shadow an explicit panel with its generated id" (acceptsPanels [
    (sdk.mkModule {
      name = "sample";
      meta.name = "Sample";
      defaultEnable = true;
      ui = sampleUi;
      panels.sample-ui.title = "Explicit";
    })
  ]) false)
  (check "standalone validator requires the advertised registration"
    (builtins.tryEval (
      sdk.validateModule {
        inherit pkgs;
        module = { };
        moduleId = "missing-example";
      }
    )).success
    false
  )
]
