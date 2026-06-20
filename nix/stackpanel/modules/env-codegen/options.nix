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
{ lib, ... }:
with lib;
{
  options.stackpanel.codegen = {
    enable = lib.mkEnableOption "Stackpanel codegen helpers";

    runOnEnter = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run enabled code generators automatically when entering the devshell.

        Keep false for slow or networked generators. Individual generators can
        override this with their `onEnter` option.
      '';
      example = true;
    };

    generators = lib.mkOption {
      description = ''
        Named code generators available to the devshell and optional shell-enter hooks.

        Each generator wraps a shell command with cwd, env, and runtimeInputs so
        generated types/clients stay reproducible.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            exec = lib.mkOption {
              type = types.str;
              description = ''
                Shell command that runs the generator.

                Example: `bun run generate:types` or `buf generate`.
              '';
              example = "bun run generate:types";
            };
            cwd = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Working directory for the generator, relative to project root.

                Null runs from the repository root.
              '';
              example = "packages/api";
            };
            env = lib.mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = ''
                Environment variables exported while running the generator.

                Use for non-secret toggles such as `NODE_ENV = "development"`.
              '';
              example = {
                NODE_ENV = "development";
              };
            };
            runtimeInputs = lib.mkOption {
              type = types.listOf types.package;
              default = [ ];
              description = ''
                Nix packages added to PATH while running this generator.

                Use for tools like `buf`, `nodejs`, `bun`, or language-specific
                codegen binaries.
              '';
              example = literalExpression "[ pkgs.bun pkgs.buf ]";
            };
            onEnter = lib.mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Whether this generator runs on devshell entry.

                Null inherits stackpanel.codegen.runOnEnter; true/false overrides
                the global default for this generator.
              '';
              example = true;
            };
          };
        }
      );
      default = { };
      example = literalExpression ''
        {
          types = {
            exec = "bun run generate:types";
            cwd = "packages/api";
            runtimeInputs = [ pkgs.bun ];
            onEnter = true;
          };
        }
      '';
    };
  };
}
