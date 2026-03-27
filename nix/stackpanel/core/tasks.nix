# ==============================================================================
# tasks.nix
#
# Task configuration options for Turborepo integration.
#
# Tasks are build pipeline steps with dependencies, caching, and outputs.
# Complex task logic is defined via `exec` + `runtimeInputs` and compiled
# to Nix derivations, then symlinked to `.tasks/bin/<task>`.
#
# Options mirror Turborepo's turbo.json schema where possible:
#   - dependsOn, outputs, inputs, cache, persistent, interactive
#
# Stackpanel-specific extensions:
#   - exec, runtimeInputs (for Nix-built scripts)
#   - before (reverse dependency convenience)
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  db = import ../db { inherit lib; };

  # Nix-only task options (runtime/build-time, not serialized to proto)
  # These use Turborepo naming conventions where applicable
  nixTaskOptionsModule =
    { lib, ... }:
    {
      options = {
        # Turborepo-compatible option (matches turbo.json naming)
        dependsOn = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Tasks that must complete before this task runs.
            Matches Turborepo's `dependsOn` option in turbo.json.

            Use `^taskname` to reference the same task in dependencies.
            Use `$taskname` for package-level dependencies.

            Example: `dependsOn = [ "deps" "^build" ];`
          '';
          example = [
            "deps"
            "^build"
          ];
        };

        # Stackpanel extension: reverse dependency convenience
        before = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            (Stackpanel extension) Tasks that depend on this task completing first.
            Automatically adds this task to the target tasks' `dependsOn`.

            Example: if `compile.before = [ "build" ]`, then
            `build.dependsOn` will automatically include `compile`.

            This is a convenience for defining dependencies from the
            dependency's perspective rather than the dependent's.
          '';
          example = [ "build" ];
        };

        # Stackpanel extension: package scope for task
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            (Stackpanel extension) Package name to scope this task to.
            When set, the task key in turbo.json becomes "package#taskName".

            This is useful for tasks that should only run in a specific package,
            such as deployment tasks that only exist in @stackpanel/infra.

            Example: `package = "@stackpanel/infra";`
          '';
          example = "@stackpanel/infra";
        };

        # Stackpanel extension: Nix packages for hermetic scripts
        runtimeInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = ''
            (Stackpanel extension) Packages to include in PATH when running the task script.
            Used with `exec` to create hermetic writeShellApplication derivations.

            These are pinned to specific Nix store paths, ensuring reproducible builds.
          '';
          example = lib.literalExpression "[ pkgs.nodejs pkgs.pnpm ]";
        };
      };
    };
in
{
  options.stackpanel.taskModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Additional modules to extend task configuration options.
    '';
  };

  options.stackpanel.tasks = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [
          # Proto-derived options (exec, description, outputs, inputs, etc.)
          { options = db.asOptions db.extend.task; }
          # Nix-only runtime options (dependsOn, before, runtimeInputs)
          nixTaskOptionsModule
        ]
        ++ config.stackpanel.taskModules;
        specialArgs = { inherit lib; };
      }
    );
    default = { };
    description = ''
      Task definitions for Turborepo integration.

      Options mirror turbo.json where possible:
        - dependsOn: Task dependencies (use ^ for workspace deps)
        - outputs: Output globs for caching
        - inputs: Input globs for cache keys
        - cache: Enable/disable caching
        - persistent: Long-running process
        - interactive: Accept stdin

      Stackpanel extensions:
        - exec: Shell script (compiled to Nix derivation)
        - runtimeInputs: Nix packages for PATH
        - before: Reverse dependency convenience

      Tasks with `exec` are compiled to Nix derivations and symlinked to
      `.tasks/bin/<task>`. Turborepo invokes these via package.json scripts.

      For ad-hoc utility scripts without build dependencies, use
      `stackpanel.scripts` instead.
    '';
    example = lib.literalExpression ''
      {
        build = {
          exec = "npm run compile";
          description = "Build all packages";
          dependsOn = [ "deps" "^build" ];
          outputs = [ "dist/**" ];
          runtimeInputs = [ pkgs.nodejs ];
        };
        dev = {
          description = "Start development servers";
          persistent = true;
          cache = false;
        };
        test = {
          exec = "vitest run";
          dependsOn = [ "^build" ];
          outputs = [ "coverage/**" ];
          runtimeInputs = [ pkgs.nodejs ];
        };
      }
    '';
  };

  # Computed task configurations (read-only, populated by turbo.nix module)
  options.stackpanel.tasksComputed = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
    readOnly = true;
    description = ''
      Computed task configurations including generated derivations and
      resolved dependencies. Populated by the turbo.nix module.
    '';
  };
}
