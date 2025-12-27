# ==============================================================================
# codegen.nix
#
# Code generation options - define and run code generators.
#
# Configures code generators that can be run automatically on shell entry
# or manually via commands. Useful for generating TypeScript types from
# schemas, API clients, or other derived code.
#
# Options:
#   - enable: Enable Stackpanel codegen helpers
#   - runOnEnter: Run generators automatically on shell entry
#   - generators: Named generators with exec, cwd, env, and runtimeInputs
#
# Usage:
#   stackpanel.codegen = {
#     enable = true;
#     generators.types = {
#       exec = "pnpm run generate:types";
#       cwd = "./packages/api";
#       onEnter = true;
#     };
#   };
# ==============================================================================
{ lib, ... }: with lib; {
  options.stackpanel.codegen = {
    enable = lib.mkEnableOption "Stackpanel codegen helpers";

    runOnEnter = lib.mkOption {
      type = types.bool;
      default = false;
    };

    generators = lib.mkOption {
      description = "Code generators to run in the devenv on shell enter.";
      type = types.attrsOf (types.submodule {
        options = {
          exec = lib.mkOption { type = types.str; };
          cwd = lib.mkOption { type = types.nullOr types.str; default = null; };
          env = lib.mkOption { type = types.attrsOf types.str; default = {}; };
          runtimeInputs = lib.mkOption { type = types.listOf types.package; default = []; };
          onEnter = lib.mkOption { type = types.nullOr types.bool; default = null; };
        };
      });
      default = {};
    };
  };
}