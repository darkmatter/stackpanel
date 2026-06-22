# ==============================================================================
# module-eval — module evaluation validator (nixtest)
#
# Evaluates a module on top of the full stackpanel schema and asserts it
# evaluates without error. This is the seed of the validator we want to run
# against community-submitted plugins: point `validateModule` at a submitted
# module and check the boolean result.
#
# What it catches (cheaply, without building derivations):
#   - syntax / import errors
#   - undefined variables
#   - definitions for options that do not exist (typos in option paths)
#   - option-merge failures
#
# It deliberately does NOT force derivations (packages, services), so it stays
# fast and pure. Deeper checks can be layered on later.
#
# Consumed by nix/flake/default.nix:
#   tests.moduleEval = nixtestLib.assertTests (nixtestLib.runTests (import ... ));
# ==============================================================================
{
  lib,
  pkgs,
  ...
}:
let
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

  # validateModule evaluates `module` within the stackpanel module system and
  # returns true iff it evaluates cleanly. Forcing the merged `config.stackpanel`
  # to an attrset (and its keys) exercises every module's option declarations
  # and `config = lib.mkIf ...` blocks, surfacing the error classes above via
  # tryEval rather than aborting the whole evaluation.
  validateModule =
    module:
    let
      probe = builtins.tryEval (
        let
          evaluated = lib.evalModules {
            modules = [
              stackpanelSchema
              module
              baseModule
            ];
          };
        in
        builtins.seq (builtins.attrNames evaluated.config.stackpanel) true
      );
    in
    probe.success && probe.value;

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
      name = "definition for a non-existent option";
      module = {
        config.stackpanel.thisOptionDoesNotExist = true;
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
    actual = validateModule case.module;
    expected = false;
  }) invalidCases;
in
positiveTests ++ negativeTests
