# ==============================================================================
# module-eval — SDK validation and full-schema regression tests (nixtest).
# ==============================================================================
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  moduleLib = import ../../../flake/module-lib.nix lib;
  # The full stackpanel schema + built-in modules (nix/stackpanel).
  stackpanelSchema = ../..;

  # Minimal config layered under every candidate so the schema is satisfiable.
  baseModule = {
    _module.args = {
      inherit pkgs;
      inputs = { };
    };
    stackpanel.enable = true;
    stackpanel.name = "module-eval";
  };

  validateModule = module: moduleLib.stackpanel.validateModule { inherit module pkgs; };

  # Modules expected to evaluate cleanly. Add plugin modules here, or call
  # `validateModule` from a plugin-submission pipeline.
  validCases = [
    {
      name = "empty module";
      module = { };
    }
    {
      name = "toggles a built-in feature";
      module = {
        config.stackpanel.theme.enable = true;
      };
    }
    {
      name = "declares and uses a custom option (plugin shape)";
      module =
        { lib, ... }:
        {
          options.stackpanel.examplePlugin.enable = lib.mkEnableOption "example plugin";
          config.stackpanel.examplePlugin.enable = true;
        };
    }
  ];

  # Negative control: defining an option that does not exist must be REJECTED,
  # proving the validator actually catches broken submissions.
  invalidCases = [
    {
      name = "extensions cannot register a module";
      module.stackpanel.extensions.sample.enabled = true;
    }
  ];

  goToolchainTests =
    let
      fakeGo =
        (pkgs.runCommand "fake-go-1.99.0" { version = "1.99.0"; } "mkdir -p $out/bin $out/share/go")
        // {
          inherit (pkgs.go) GOOS GOARCH CGO_ENABLED;
        };
      evaluated = lib.evalModules {
        modules = [
          stackpanelSchema
          baseModule
          {
            config.stackpanel = {
              process-compose.enable = false;
              languages.go.package = fakeGo;
              apps.demo = {
                path = "apps/demo";
                go.enable = true;
              };
            };
          }
        ];
        specialArgs = {
          inherit pkgs;
          lib = moduleLib;
          isGlobalEval = false;
          self = {
            outPath = ../../..;
          };
          localFlake = null;
          inputs = { };
        };
      };
      sp = evaluated.config.stackpanel;
      devshellDrvs = map (p: p.drvPath) (builtins.filter lib.isDerivation sp.devshell.packages);
      gomod2nixOverridden =
        if pkgs ? gomod2nix then (pkgs.gomod2nix.override { go = fakeGo; }).drvPath else null;
      runScriptDrv = sp.scriptsConfig.packages."run-demo".drvAttrs;
      runScriptBody = builtins.unsafeDiscardStringContext (
        (runScriptDrv.text or "") + (runScriptDrv.buildCommand or "")
      );
    in
    [
      {
        name = "go-toolchain: Go app auto-enables languages.go";
        actual = sp.languages.go.enable;
        expected = true;
      }
    ]
    ++ lib.optionals (pkgs ? gomod2nix) [
      {
        name = "go-toolchain: languages.go wraps gomod2nix with configured package";
        actual = builtins.elem gomod2nixOverridden devshellDrvs;
        expected = true;
      }
    ]
    ++ [
      {
        name = "go-toolchain: run-<app> script uses configured languages.go.package";
        actual = lib.hasInfix "fake-go-1.99.0" runScriptBody;
        expected = true;
      }
      {
        name = "go-toolchain: native overview shows the configured Go version and Go app count";
        actual =
          let
            panel = sp.panelsComputed.go-status;
          in
          {
            inherit (panel) type slot title;
            version = panel.spec.elements.version.props.value;
            apps = panel.spec.elements.apps.props.value;
          };
        expected = {
          type = "PANEL_TYPE_SPEC";
          slot = "overview";
          title = "Go Environment";
          version = "1.99.0";
          apps = 1;
        };
      }
    ];

  positiveTests = map (case: {
    name = "module-eval (valid): ${case.name}";
    actual = validateModule case.module;
    expected = true;
  }) validCases;

  negativeTests = map (case: {
    name = "module-eval (invalid): ${case.name}";
    actual = (builtins.tryEval (validateModule case.module)).success;
    expected = false;
  }) invalidCases;
in
positiveTests
++ negativeTests
++ goToolchainTests
++ (import ./sdk.nix { inherit lib pkgs; })
++ (import ./ui.nix { inherit lib; })
++ (import ./providers.nix {
  inherit pkgs;
  lib = moduleLib;
})
++ (import ../../integrations/containers/provider-tests.nix { inherit lib pkgs inputs; })
