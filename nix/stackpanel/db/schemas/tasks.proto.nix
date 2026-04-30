# ==============================================================================
# tasks.proto.nix
#
# Protobuf schema for task configuration with Turborepo integration.
#
# Tasks are build pipeline steps with dependencies, caching, and outputs.
# Complex task logic is defined via `exec` and compiled to Nix derivations,
# then symlinked to `.tasks/bin/<task>` for Turborepo to invoke.
#
# For ad-hoc utility scripts without dependencies, use stackpanel.scripts.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "tasks.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # tasks.nix - Workspace tasks (Turborepo pipeline)
    # type: sp-task
    # See: https://stackpanel.dev/docs/tasks
    {
      # Example tasks (mirrors turbo.json options):
      # build = {
      #   exec = "npm run compile";
      #   description = "Build all packages";
      #   dependsOn = [ "^build" "deps" ];
      #   outputs = [ "dist/**" ];
      #   inputs = [ "$TURBO_DEFAULT$" ];
      # };
      #
      # dev = {
      #   description = "Start development servers";
      #   persistent = true;
      #   cache = false;
      # };
      #
      # test = {
      #   exec = "vitest run";
      #   dependsOn = [ "build" ];
      #   outputs = [ "coverage/**" ];
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    Task = proto.mkMessage {
      name = "Task";
      description = ''
        A workspace task definition for Turborepo integration.

        Tasks with `exec` are compiled to Nix derivations and symlinked to
        `.tasks/bin/<task>`. Turborepo invokes these via package.json scripts.

        Tasks without `exec` assume the script already exists in package.json.
      '';
      fields = {
        # Script definition (stackpanel-specific)
        exec = proto.optional (proto.withExample "bun run build" (proto.string 1 "Shell script to execute (compiled to Nix derivation)"));
        description = proto.optional (proto.withExample "Build all packages" (proto.string 2 "Human-readable description of the task"));
        cwd = proto.optional (proto.withExample "apps/web" (proto.string 3 "Working directory for the task (relative to repo root)"));
        env = proto.map "string" "string" 4 "Environment variables for the task";

        # Turborepo configuration (mirrors turbo.json schema)
        depends_on = proto.repeated (proto.withExample "^build" (proto.string 5 "Tasks that must complete first (use ^ for deps)"));
        outputs = proto.repeated (proto.withExample "dist/**" (proto.string 6 "Output file globs for caching (e.g. dist/**)"));
        inputs = proto.repeated (proto.withExample "$TURBO_DEFAULT$" (proto.string 7 "Input file globs for cache key (e.g. $TURBO_DEFAULT$)"));
        persistent = proto.optional (proto.withExample false (proto.bool 8 "Long-running process (e.g. dev server)"));
        cache = proto.optional (proto.withExample true (proto.bool 9 "Enable Turborepo caching (default: true)"));
        interactive = proto.optional (proto.withExample false (proto.bool 10 "Task accepts stdin input"));
      };
    };

    Tasks = proto.mkMessage {
      name = "Tasks";
      description = "Primary workspace tasks configuration for Turborepo";
      fields = {
        tasks = proto.map "string" "Task" 1 "Map of task name to task config";
      };
    };
  };
}
