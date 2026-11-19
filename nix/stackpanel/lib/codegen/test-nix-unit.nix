# Test suite for stackpanel lib functions using nix-unit
#
# Run with:
#   nix run github:adisbladis/nix-unit -- --impure nix/stackpanel/lib/codegen/test-nix-unit.nix
#
# nix-unit discovers tests by walking the attrset tree. Leaf test attrs must
# be prefixed with "test_" and have { expr = <actual>; expected = <expected>; }.
# Non-test groups can have any name — only leaves need the prefix.
let
  pkgs = import <nixpkgs> { };
  inherit (pkgs) lib;

  portsLib = import ../ports.nix { inherit lib; };
  serializeLib = import ../serialize.nix { inherit lib; };
  pathsLib = import ../paths.nix { inherit lib; };
in
{
  panels =
    let
      builders = import ../panels.nix { inherit lib; };
      sp = import ../../db/lib/field.nix { inherit lib; };
      fields = {
        hotReload = sp.bool { index = 1; };
        private = sp.string {
          index = 2;
          ui = null;
        };
      };
      scoped = {
        inherit fields;
        title = "Build settings";
        module = "builder";
      };
      bundle = pkgs.writeTextDir "index.html" "<!doctype html>";
      evaluated =
        (lib.evalModules {
          modules = [
            ../../core/options/panels.nix
            {
              stackpanel.panels = {
                app = builders.mkPanelFromSpFields (
                  scoped
                  // {
                    optionPrefix = "framework.demo";
                    apps.web.framework.demo.hotReload = false;
                    slot = "app:framework";
                  }
                );
                settings = builders.mkPanelFromModuleFields (scoped // { values.hotReload = true; });
                home = {
                  module = "builder";
                  title = "Home";
                  slot = "sidebar";
                  nav.section = "Workspace";
                  type = "PANEL_TYPE_TABS";
                  tabs = [
                    "settings"
                    "custom"
                  ];
                  actions = [ "refresh" ];
                };
                custom = {
                  module = "builder";
                  title = "Preview";
                  type = "PANEL_TYPE_CUSTOM";
                  uiBundle = {
                    package = bundle;
                    permissions = [ "config:read" ];
                  };
                };
                restricted = {
                  module = "builder";
                  title = "Limited";
                  type = "PANEL_TYPE_CUSTOM";
                  uiBundle = {
                    package = bundle;
                    permissions = [ "actions:run" ];
                    actionIds = [ "refresh" ];
                  };
                };
                denied = {
                  module = "builder";
                  title = "No actions";
                  type = "PANEL_TYPE_CUSTOM";
                  uiBundle = {
                    package = bundle;
                    permissions = [ "actions:run" ];
                    actionIds = [ ];
                  };
                };
              };
            }
          ];
        }).config.stackpanel.panelsComputed;
    in
    {
      test_scoped_app_fields = {
        expr = {
          inherit (evaluated.app.apps.web) config;
          path = (builtins.head evaluated.app.fields).editPath;
        };
        expected = {
          config.hotReload = "false";
          path = "framework.demo.hotReload";
        };
      };
      test_module_field = {
        expr = map (f: { inherit (f) configPath value; }) evaluated.settings.fields;
        expected = [
          {
            configPath = "modules.builder.settings.hotReload";
            value = "true";
          }
        ];
      };
      test_slot = {
        expr = {
          inherit (evaluated.home)
            slot
            nav
            tabs
            actions
            ;
        };
        expected = {
          slot = "sidebar";
          nav.section = "Workspace";
          tabs = [
            "settings"
            "custom"
          ];
          actions = [ "refresh" ];
        };
      };
      test_store_bundle = {
        expr = evaluated.custom.uiBundle;
        expected = {
          package = toString bundle;
          drvPath = toString bundle.drvPath;
          entry = "index.html";
          permissions = [ "config:read" ];
          actionIds = null;
        };
      };
      test_bundle_action_allowlist_json = {
        expr = builtins.toJSON (
          map (p: p.uiBundle.actionIds) [
            evaluated.custom
            evaluated.restricted
            evaluated.denied
          ]
        );
        expected = ''[null,["refresh"],[]]'';
      };
      test_action = {
        expr = builders.mkJsonAction {
          script = "builder-refresh";
          label = "Refresh";
        };
        expected = {
          script = "builder-refresh";
          label = "Refresh";
          outputMode = "json";
        };
      };
    };

  # ===========================================================================
  # ports
  # ===========================================================================
  ports = {
    computeBasePort = {
      test_deterministic = {
        expr = portsLib.computeBasePort { name = "myproject"; };
        expected = portsLib.computeBasePort { name = "myproject"; };
      };

      test_different_names_differ = {
        expr = portsLib.computeBasePort { name = "alpha"; } != portsLib.computeBasePort { name = "beta"; };
        expected = true;
      };

      test_within_range =
        let
          port = portsLib.computeBasePort { name = "testproject"; };
        in
        {
          expr = port >= portsLib.constants.MIN_PORT && port < portsLib.constants.MAX_PORT;
          expected = true;
        };

      test_rounds_to_modulus =
        let
          port = portsLib.computeBasePort { name = "anything"; };
        in
        {
          expr = lib.mod port portsLib.constants.MODULUS;
          expected = 0;
        };
    };

    computeOverRange = {
      test_within_bounds =
        let
          result = portsLib.computeOverRange {
            key = "test";
            min = 3000;
            max = 10000;
            modulus = 100;
          };
        in
        {
          expr = result >= 3000 && result < 10000;
          expected = true;
        };

      test_respects_modulus =
        let
          result = portsLib.computeOverRange {
            key = "test";
            min = 3000;
            max = 10000;
            modulus = 100;
          };
        in
        {
          expr = lib.mod result 100;
          expected = 0;
        };
    };

    stablePort = {
      test_deterministic = {
        expr = portsLib.stablePort {
          repo = "myproject";
          service = "postgres";
        };
        expected = portsLib.stablePort {
          repo = "myproject";
          service = "postgres";
        };
      };

      test_different_services_differ = {
        expr =
          portsLib.stablePort {
            repo = "proj";
            service = "postgres";
          } != portsLib.stablePort {
            repo = "proj";
            service = "redis";
          };
        expected = true;
      };

      test_within_project_range =
        let
          base = portsLib.computeBasePort { name = "proj"; };
          port = portsLib.stablePort {
            repo = "proj";
            service = "postgres";
          };
        in
        {
          expr = port >= base && port < base + portsLib.constants.MODULUS;
          expected = true;
        };
    };

    computeServicePort = {
      test_basic = {
        expr = portsLib.computeServicePort {
          basePort = 6400;
          index = 0;
        };
        expected = 6410;
      };

      test_with_index = {
        expr = portsLib.computeServicePort {
          basePort = 6400;
          index = 3;
        };
        expected = 6413;
      };
    };

    computeServicesWithPorts = {
      test_correct_length = {
        expr = builtins.length (
          portsLib.computeServicesWithPorts {
            basePort = 6400;
            services = [
              { key = "postgres"; }
              { key = "redis"; }
            ];
          }
        );
        expected = 2;
      };

      test_correct_ports = {
        expr = map (s: s.port) (
          portsLib.computeServicesWithPorts {
            basePort = 6400;
            services = [
              { key = "postgres"; }
              { key = "redis"; }
            ];
          }
        );
        expected = [
          6410
          6411
        ];
      };
    };

    computeServicesFromAttrset = {
      test_has_correct_keys =
        let
          result = portsLib.computeServicesFromAttrset {
            projectName = "myproj";
            services = {
              postgres = {
                name = "PostgreSQL";
              };
              redis = {
                name = "Redis";
              };
            };
          };
        in
        {
          expr = builtins.attrNames result;
          expected = [
            "postgres"
            "redis"
          ];
        };

      test_includes_port =
        let
          result = portsLib.computeServicesFromAttrset {
            projectName = "myproj";
            services = {
              postgres = {
                name = "PostgreSQL";
              };
            };
          };
        in
        {
          expr = result.postgres ? port;
          expected = true;
        };
    };

    mkPortsConfig = {
      test_has_all_fields =
        let
          config = portsLib.mkPortsConfig {
            projectName = "test";
            services = [ { key = "postgres"; } ];
          };
        in
        {
          expr = builtins.attrNames config;
          expected = [
            "basePort"
            "env"
            "servicesByKey"
            "servicesConfig"
            "servicesWithPorts"
          ];
        };
    };
  };

  # ===========================================================================
  # serialize
  # ===========================================================================
  serialize = {
    isSerializable = {
      test_string = {
        expr = serializeLib.isSerializable "hello";
        expected = true;
      };
      test_int = {
        expr = serializeLib.isSerializable 42;
        expected = true;
      };
      test_float = {
        expr = serializeLib.isSerializable 3.14;
        expected = true;
      };
      test_bool = {
        expr = serializeLib.isSerializable true;
        expected = true;
      };
      test_null = {
        expr = serializeLib.isSerializable null;
        expected = true;
      };
      test_list = {
        expr = serializeLib.isSerializable [
          1
          "two"
          true
        ];
        expected = true;
      };
      test_attrset = {
        expr = serializeLib.isSerializable {
          a = 1;
          b = "two";
        };
        expected = true;
      };
      test_lambda = {
        expr = serializeLib.isSerializable (x: x);
        expected = false;
      };
      test_derivation = {
        expr = serializeLib.isSerializable { type = "derivation"; };
        expected = false;
      };
      test_functor = {
        expr = serializeLib.isSerializable { __functor = _: _: null; };
        expected = false;
      };
      test_nested_valid = {
        expr = serializeLib.isSerializable {
          a = {
            b = [
              1
              2
              3
            ];
            c = "hello";
          };
        };
        expected = true;
      };
      test_nested_with_lambda_is_shallow = {
        expr = serializeLib.isSerializable {
          a = {
            b = x: x;
          };
        };
        expected = true;
      };
      test_list_with_lambda = {
        expr = serializeLib.isSerializable [
          1
          (x: x)
          3
        ];
        expected = false;
      };
    };

    filterSerializable = {
      test_removes_lambdas = {
        expr = serializeLib.filterSerializable {
          a = 1;
          b = x: x;
          c = "kept";
        };
        expected = {
          a = 1;
          c = "kept";
        };
      };
      test_passes_primitives = {
        expr = serializeLib.filterSerializable "hello";
        expected = "hello";
      };
      test_null_for_lambda = {
        expr = serializeLib.filterSerializable (x: x);
        expected = null;
      };
      test_recursive_attrset = {
        expr = serializeLib.filterSerializable {
          top = {
            keep = 42;
            drop = x: x;
          };
        };
        expected = {
          top = {
            keep = 42;
          };
        };
      };
    };

    filterSerializableWithSkip = {
      test_skips_keys = {
        expr = serializeLib.filterSerializableWithSkip [ "secret" ] {
          public = "visible";
          secret = "hidden";
        };
        expected = {
          public = "visible";
        };
      };
    };

    projectState =
      let
        private = throw "the public projection forced a private value";
        cfg = {
          modules = {
            alpha = { };
            beta = { };
            inactive = { };
          };
          modulesListAll = [
            {
              id = "alpha";
              enabled = true;
            }
            {
              id = "inactive";
              enabled = false;
            }
          ];
          panelsList = [
            {
              id = "summary";
              module = "alpha";
              slot = "sidebar";
            }
          ];
          lazyNamespaces = [ "expensive" ];
          expensive = private;
          outputs = private;
          appBuildProviders = private;
          appFrameworks.demo = {
            label = "Demo";
            module = "alpha";
            deployMetadata = private;
          };
          apps.web.framework.demo.enable = true;
          apps.web.tasks.build = {
            module = "beta";
            exec = private;
          };
          serializable.expensive = {
            count = 2;
          };
          files.entries."package.json" = {
            module = "alpha";
            modules = [
              "alpha"
              "beta"
            ];
            format = "json";
            value = private;
          };
          modulePackages.alpha = [
            {
              pname = "example";
              version = "1";
              outPath = private;
            }
          ];
          scripts.run = {
            module = "alpha";
            env = private;
            exec = private;
          };
          devshell = {
            env = private;
            _commandsSerializable.run.binPath = "/nix/store/example/bin/run";
          };
          tasks.build = {
            module = "alpha";
            runtimeInputs = private;
          };
          doctorList = [
            {
              module = "alpha";
              id = "alpha-build";
              scope = "build";
              drvPath = private;
            }
          ];
          services.server = {
            module = "alpha";
            env = private;
            proxy = {
              enable = true;
              port = 8000;
            };
          };
        };
        # Force the entire JSON payload, not just the part being asserted on.
        state = builtins.fromJSON (builtins.toJSON (serializeLib.projectState cfg));
      in
      {
        test_all_declarations_indexed_once = {
          expr = lib.mapAttrs (_: builtins.length) state.moduleOutputs.alpha;
          expected = {
            files = 1;
            scripts = 1;
            services = 1;
            tasks = 1;
            packages = 1;
            healthchecks = 1;
          };
        };
        test_shared_file_ownership = {
          expr = map (f: f.path) state.moduleOutputs.beta.files;
          expected = [ "package.json" ];
        };
        test_app_task_ownership = {
          expr = map (t: t.name) state.moduleOutputs.beta.tasks;
          expected = [ "web:build" ];
        };
        test_inactive_module_visible = {
          expr = state.modulesListAll;
          expected = cfg.modulesListAll;
        };
        test_panels_consistent = {
          expr = state.panelsList;
          expected = cfg.panelsList;
        };
        test_lazy_public_namespace = {
          expr = state.expensive;
          expected = cfg.serializable.expensive;
        };
        test_framework_selector = {
          expr = state.apps.web.framework.demo.enable;
          expected = true;
        };
        test_proxy_port = {
          expr = (builtins.head state.moduleOutputs.alpha.services).proxy.port;
          expected = 8000;
        };
        test_immutable_script = {
          expr = (builtins.head state.moduleOutputs.alpha.scripts).binPath;
          expected = cfg.devshell._commandsSerializable.run.binPath;
        };
      };

    test_proxy_port_inventory = {
      expr = serializeLib.proxyPortInventory {
        private = {
          enable = true;
          port = 8000;
          proxy = {
            enable = false;
            port = 9999;
          };
        };
        api = {
          enable = true;
          port = 8000;
          proxy = {
            enable = true;
            port = 7000;
          };
        };
        worker = {
          enable = true;
          port = null;
          proxy = {
            enable = true;
            port = null;
          };
        };
        disabled = {
          enable = false;
          port = abort "disabled service was forced";
        };
      };
      expected = {
        schemaVersion = 1;
        ports = [
          7000
          8000
        ];
      };
    };

    test_trusted_and_module_projections =
      let
        secret = "example-private-value";
        cfg = {
          modulesListAll = [ ];
          apps.web.deployment.backend = "demo";
          apps.web.env.DATABASE_URL.value = secret;
          variables."/dev/DATABASE_URL".value = secret;
          devshell.env.DATABASE_URL = secret;
          lazyNamespaces = [ "buildData" ];
          buildData = abort "walked opaque buildData";
          outputs = abort "walked outputs";
          doctorList = [
            {
              scope = "build";
              module = "example";
              checkName = "example-build";
              drvPath = abort "forced a build check";
            }
          ];
        };
        public = builtins.toJSON (serializeLib.projectState cfg);
        full = builtins.fromJSON (builtins.toJSON (serializeLib.projectConfig cfg));
      in
      {
        expr = [
          (lib.hasInfix secret public)
          full.apps.web.deployment.backend
          full.devshell.env.DATABASE_URL
          full.variables."/dev/DATABASE_URL".value
          (builtins.head full.doctorList).checkName
        ];
        expected = [
          false
          "demo"
          secret
          secret
          "example-build"
        ];
      };

    trySerialize = {
      test_valid_json = {
        expr = serializeLib.trySerialize { a = 1; };
        expected = "{\"a\":1}";
      };
    };

    serializePackage = {
      test_with_name = {
        expr = serializeLib.serializePackage {
          name = "hello";
          version = "1.0";
          meta = { };
        };
        expected = {
          name = "hello";
          version = "1.0";
          attrPath = "hello";
          source = "devshell";
        };
      };
      test_from_string = {
        expr = serializeLib.serializePackage "my-tool";
        expected = {
          name = "my-tool";
          version = "";
          attrPath = "my-tool";
          source = "devshell";
        };
      };
    };
  };

  # ===========================================================================
  # paths
  # ===========================================================================
  paths = {
    mkPaths = {
      test_defaults = {
        expr = pathsLib.mkPaths { };
        expected = {
          root = ".stack";
          state = ".stack/state";
          gen = ".stack/gen";
          keys = ".stack/keys";
          config = null;
        };
      };
      test_custom_root = {
        expr = pathsLib.mkPaths { rootDir = ".mystack"; };
        expected = {
          root = ".mystack";
          state = ".mystack/state";
          gen = ".mystack/gen";
          keys = ".mystack/keys";
          config = null;
        };
      };
      test_custom_subdirs = {
        expr = pathsLib.mkPaths {
          rootDir = ".stack";
          stateDir = "runtime";
          genDir = "generated";
          keysDir = "certs";
        };
        expected = {
          root = ".stack";
          state = ".stack/runtime";
          gen = ".stack/generated";
          keys = ".stack/certs";
          config = null;
        };
      };
      test_with_config_dir = {
        expr = (pathsLib.mkPaths { configDir = "/etc/stack"; }).config;
        expected = "/etc/stack";
      };
    };

    mkGitignore = {
      test_default = {
        expr = pathsLib.mkGitignore { };
        expected = "state/";
      };
      test_custom_state_dir = {
        expr = pathsLib.mkGitignore { stateDir = "runtime"; };
        expected = "runtime/";
      };
      test_extra_entries = {
        expr = pathsLib.mkGitignore {
          extraEntries = [
            "*.tmp"
            "local.nix"
          ];
        };
        expected = "state/\n*.tmp\nlocal.nix";
      };
    };

    defaults = {
      test_exist = {
        expr = pathsLib.defaults;
        expected = {
          rootDir = ".stack";
          stateDir = "state";
          keysDir = "keys";
          genDir = "gen";
        };
      };
    };

    validation = {
      test_rejects_full_state_path =
        let
          threw = !(builtins.tryEval (pathsLib.mkShellPathUtils { stateDir = ".stack/state"; })).success;
        in
        {
          expr = threw;
          expected = true;
        };
      test_rejects_full_gen_path =
        let
          threw = !(builtins.tryEval (pathsLib.mkShellPathUtils { genDir = ".stack/gen"; })).success;
        in
        {
          expr = threw;
          expected = true;
        };
      test_accepts_valid_subdirs =
        let
          succeeded =
            (builtins.tryEval (
              pathsLib.mkShellPathUtils {
                stateDir = "state";
                genDir = "gen";
              }
            )).success;
        in
        {
          expr = succeeded;
          expected = true;
        };
    };
  };
}
