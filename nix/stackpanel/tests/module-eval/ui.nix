# The public SDK, project panels and module-author option tree must agree on the
# author format. Compare against the Studio wire document, not compiler internals.
{ lib }:
let
  moduleLib = import ../../../flake/module-lib.nix lib;
  inherit (moduleLib.stackpanel) ui mkModule moduleAuthorOptions;
  check = name: actual: expected: {
    name = "UI: ${name}";
    inherit actual expected;
  };
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;

  metricProps = {
    label = "Apps";
    value = 2;
  };
  metric = ui.metric metricProps;
  single = widget: { widgets.count = widget; };
  stack = children: { stack = { inherit children; }; };
  live = {
    state = {
      data.apps = [
        "web"
        "worker"
      ];
      local.selection = "worker";
    };
    widgets = {
      overview.stack = {
        direction = "vertical";
        children = [
          "picker"
          "details"
        ]; # Deliberately not lexical order.
      };
      picker.appPicker = {
        apps = ui.read "/data/apps";
        value = ui.bindLocal "selection";
      };
      details.section = {
        title = ui.read "/panel/title";
        children = [ "status" ];
      };
      status.statusView = {
        action = "inspect";
        app = ui.read "/local/selection";
      };
    };
  };
  liveSpec = {
    root = "overview";
    inherit (live) state;
    elements = {
      overview = {
        type = "Stack";
        props.direction = "vertical";
        children = [
          "picker"
          "details"
        ];
      };
      picker = {
        type = "AppPicker";
        props.apps."$state" = "/data/apps";
        props.value."$bindState" = "/local/selection";
      };
      details = {
        type = "Section";
        props.title."$state" = "/panel/title";
        children = [ "status" ];
      };
      status = {
        type = "StatusView";
        props.action = "inspect";
        props.app."$state" = "/local/selection";
      };
    };
  };

  # No full project or packages needed: these are the actual panel/registry
  # options used at both entry points. Keep their input identical for parity.
  evaluate =
    document:
    lib.evalModules {
      specialArgs.lib = moduleLib;
      modules = [
        ../../core/options/modules.nix
        ../../core/options/panels.nix
        (mkModule {
          name = "sample";
          meta.name = "Sample";
          defaultEnable = true;
          ui = document;
        })
        {
          stackpanel.panels.project = {
            module = "sample";
            title = "Project";
            spec = document;
          };
        }
      ];
    };
  panelsFor = document: (evaluate document).config.stackpanel.panelsComputed;
  bothSpecs =
    document:
    let
      panels = panelsFor document;
    in
    [
      panels.project.spec
      panels.sample-ui.spec
    ];
  rawFile = ../../../flake/templates/_test-fixtures/external-module/test-module/studio.json;
  raw = lib.importJSON rawFile;

  # Follow real option types just as a documentation/completion consumer would.
  sub = option: option.type.getSubOptions option.loc;
  catalog = (lib.importJSON ../../lib/ui/widget-catalog.v1.json).components;
  lowerFirst = s: lib.toLower (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;
  kindNames = map lowerFirst (builtins.attrNames catalog);
  # nixd renders every matching option, not just the selected one. A relative
  # declaration file (e.g. `<unknown-file>`) can abort its URI conversion.
  hasSource =
    option:
    option.declarationPositions != [ ]
    && lib.all (p: lib.hasPrefix "/" (toString p.file)) option.declarationPositions;
  inspect =
    prefix: document:
    let
      kinds = sub document.widgets;
      metricOptions = sub kinds.metric;
      columns = (sub kinds.table).columns;
      column = sub columns;
      propPath = prefix ++ [
        "widgets"
        "<name>"
      ];
    in
    check "${lib.showOption prefix}: native completion and hover"
      {
        widgetType = [
          document.widgets.type.name
          document.widgets.type.nestedTypes.elemType.name
        ];
        kinds = builtins.attrNames (removeAttrs kinds [ "_module" ]);
        stateAndRoot = lib.all lib.isOption [
          document.state.data
          document.state.local
          document.root
        ];
        completionSources = lib.all hasSource (
          [
            document.widgets
            document.root
            document.state.data
            document.state.local
          ]
          ++ lib.collect lib.isOption kinds
          ++ lib.collect lib.isOption metricOptions
          ++ lib.collect lib.isOption column
        );
        metricLabel = metricOptions.label.description;
        labelHasType = lib.isOption metricOptions.label && metricOptions.label.type.description != "";
        labelPath = metricOptions.label.loc;
        columnPath = column.key.loc;
        columnDocs = [
          column.key.description
          column.label.description
        ];
        layout = (sub kinds.stack) ? children && !((sub kinds.metric) ? children);
        hostOnly = (sub kinds.statusView) ? allowedApps;
      }
      {
        widgetType = [
          "attrsOf"
          "submodule"
        ];
        kinds = lib.sort builtins.lessThan kindNames;
        stateAndRoot = true;
        completionSources = true;
        metricLabel = catalog.Metric.props.properties.label.description;
        labelHasType = true;
        labelPath = propPath ++ [
          "metric"
          "label"
        ];
        columnPath = propPath ++ [
          "table"
          "columns"
          "*"
          "key"
        ];
        columnDocs =
          let
            fields = catalog.Table.props.properties.columns.items.properties;
          in
          [
            fields.key.description
            fields.label.description
          ];
        layout = true;
        hostOnly = false;
      };
  panelOptions = (evaluate live).options.stackpanel.panels;
  panelSpec = panels: (sub panels).spec;

  # Build otherwise valid trees on both sides of each graph limit, so the
  # test can't pass just because the generated shape is invalid for all sizes.
  wide =
    count:
    let
      names = builtins.genList (n: "n${toString n}") (count - 1);
    in
    {
      widgets = lib.genAttrs names (_: metric) // {
        root = stack names;
      };
    };
  deep = count: {
    widgets = builtins.listToAttrs (
      builtins.genList (n: {
        name = "n${toString n}";
        value = if n + 1 == count then metric else stack [ "n${toString (n + 1)}" ];
      }) count
    );
  };
  typo = single {
    metric = metricProps // {
      lable = "Typo";
    };
  };
  picker = live.widgets.picker.appPicker;
  column = {
    key = "ready";
    label = "Ready";
  };
  table = {
    columns = [ column ];
    rows = [
      { ready = false; }
      { ready = null; }
    ];
  };
  invalid = {
    "unknown envelope option" = live // {
      widgtes = { };
    };
    "mixed elements and widgets" = live // {
      inherit (liveSpec) elements;
    };
    "unknown kind" = single { metrix = metricProps; };
    "no kind" = single { };
    "two kinds" = single (metric // { text.content = "Other"; });
    "extra prop even when required props are valid" = typo;
    "missing required prop" = single { metric.label = "Apps"; };
    "invalid required union prop" = single {
      metric = metricProps // {
        value = true;
      };
    };
    "invalid enum member" = single { stack.direction = "diagonal"; };
    "nested column typo" = single {
      table = table // {
        columns = [ (column // { lable = "typo"; }) ];
      };
    };
    "empty required columns" = single {
      table = table // {
        columns = [ ];
      };
    };
    "too many action IDs" = single { actions.ids = builtins.genList (n: "action${toString n}") 33; };
    "read in literal-only action" = single { statusView.action = ui.read "/module/id"; };
    "undeclared state read" = single {
      metric = metricProps // {
        value = ui.read "/data/missing";
      };
    };
    "read resolves to the wrong prop type" =
      (single {
        metric = metricProps // {
          value = ui.read "/data/ready";
        };
      })
      // {
        state.data.ready = true;
      };
    "picker cannot write through a read" =
      (single {
        appPicker = picker // {
          value = ui.read "/local/selection";
        };
      })
      // {
        inherit (live) state;
      };
    "status cannot read data as its app" =
      (single {
        statusView = {
          action = "inspect";
          app = ui.read "/data/app";
        };
      })
      // {
        state.data.app = "web";
      };
    "children not supported by a leaf" = {
      widgets.count.metric = metricProps // {
        children = [ "message" ];
      };
      widgets.message.text.content = "Child";
    };
    "empty tree" = {
      widgets = { };
    };
    "ambiguous inferred root" = {
      widgets = {
        a = metric;
        b = metric;
      };
    };
    "unreachable from explicit root" = {
      root = "a";
      widgets = {
        a = metric;
        b = metric;
      };
    };
    "unknown explicit root" = (single metric) // {
      root = "missing";
    };
    "missing child" = single (stack [ "missing" ]);
    "duplicate child" = {
      widgets = {
        a = stack [
          "b"
          "b"
        ];
        b = metric;
      };
    };
    "shared child" = {
      widgets = {
        a = stack [
          "b"
          "c"
        ];
        b = stack [ "c" ];
        c = metric;
      };
    };
    "cycle" = {
      root = "a";
      widgets = {
        a = stack [ "b" ];
        b = stack [ "a" ];
      };
    };
    "unsafe widget ID" = {
      widgets."bad/id" = metric;
    };
    "65 widgets" = wide 65;
    "17 levels" = deep 17;
  };
in
[
  (check "constructors use catalog kind names" (lib.all (
    k: builtins.isFunction ui.${k}
  ) kindNames) true)
  (check "metric constructor is a reusable author fragment" metric { metric = metricProps; })
  (check "one metric infers its own root" (ui.compile (single metric)) {
    root = "count";
    elements.count = {
      type = "Metric";
      props = metricProps;
    };
  })
  (check "nested table columns and nullable cells retain their shape"
    (ui.compile (single {
      inherit table;
    })).elements.count.props
    table
  )
  (check "live bindings and ordered children survive root inference" (ui.compile live) liveSpec)
  (check "explicit root yields the same flat tree" (ui.compile (
    live // { root = "overview"; }
  )) liveSpec)
  (check "project spec and mkModule.ui emit the Studio document" (bothSpecs live) [
    liveSpec
    liveSpec
  ])
  (check "project spec and mkModule.ui both reject the typo" (map succeeds (bothSpecs typo)) [
    false
    false
  ])
  (check "raw inline spec is passed to Studio unchanged" (bothSpecs raw) [
    raw
    raw
  ])
  (check "JSON file spec is passed to Studio unchanged" (bothSpecs rawFile) [
    raw
    raw
  ])
  (check "graph limits include 64 widgets and 16 levels"
    (map (doc: succeeds (ui.compile doc)) [
      (wide 64)
      (deep 16)
    ])
    [
      true
      true
    ]
  )
  (check "panel types expose a nixd-traversable spec"
    (map
      (panels: [
        panels.type.name
        panels.type.nestedTypes.elemType.name
        (panelSpec panels).type.name
      ])
      [
        moduleAuthorOptions.panels
        panelOptions
      ]
    )
    [
      [
        "attrsOf"
        "submodule"
        "submodule"
      ]
      [
        "attrsOf"
        "submodule"
        "submodule"
      ]
    ]
  )
  (inspect [ "ui" ] moduleAuthorOptions.ui)
  (inspect [ "panels" "<name>" "spec" ] (sub (panelSpec moduleAuthorOptions.panels)))
  (inspect [ "stackpanel" "panels" "<name>" "spec" ] (sub (panelSpec panelOptions)))
]
++ lib.mapAttrsToList (name: doc: check "rejects ${name}" (succeeds (ui.compile doc)) false) invalid
