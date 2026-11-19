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

  goOverviewTest =
    let
      evaluated = lib.evalModules {
        modules = [
          stackpanelSchema
          baseModule
          {
            config.stackpanel = {
              process-compose.enable = false;
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
      panel = evaluated.config.stackpanel.panelsComputed.go-status;
    in
    {
      name = "go: native overview shows the Go version and configured app count";
      actual = { inherit (panel) type slot; version = panel.spec.elements.version.props.value; apps = panel.spec.elements.apps.props.value; };
      expected = { type = "PANEL_TYPE_SPEC"; slot = "overview"; version = pkgs.go.version; apps = 1; };
    };

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
++ [ goOverviewTest ]
++ (import ./sdk.nix { inherit lib pkgs; })
++ (import ./ui.nix { inherit lib; })
++ (import ./providers.nix {
  inherit pkgs;
  lib = moduleLib;
})
++ (import ../../integrations/containers/provider-tests.nix { inherit lib pkgs inputs; })
