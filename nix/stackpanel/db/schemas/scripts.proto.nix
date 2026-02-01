# ==============================================================================
# scripts.proto.nix
#
# Protobuf schema for script configuration.
#
# Scripts are ad-hoc utility commands exposed in the development shell.
# Unlike tasks (which have build dependencies and caching), scripts are
# simple executable commands bundled into a single package with bin/.
#
# For build pipeline tasks with dependencies, use stackpanel.tasks instead.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "scripts.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # scripts.nix - Development shell scripts
    # type: sp-script
    # See: https://stackpanel.dev/docs/scripts
    {
      # Example scripts:
      # db-seed = {
      #   exec = "npm run seed";
      #   description = "Seed the database with test data";
      # };
      #
      # "api:start" = {
      #   exec = "bun run dev";
      #   description = "Start the API server";
      # };
      #
      # format = {
      #   exec = "biome format --write .";
      #   description = "Format all source files";
      # };
      #
      # # Script with documented arguments:
      # deploy = {
      #   exec = "deploy.sh \"$@\"";
      #   description = "Deploy the application to an environment";
      #   args = [
      #     { name = "environment"; description = "Target environment (dev, staging, prod)"; required = true; }
      #     { name = "--dry-run"; description = "Preview changes without applying"; }
      #     { name = "--force"; description = "Skip confirmation prompts"; }
      #   ];
      # };
      #
      # # Script with custom timeout (60 seconds):
      # api-healthcheck = {
      #   exec = "curl -f http://localhost:3000/health";
      #   description = "Check API health";
      #   timeout = 60;  # 1 minute timeout
      # };
      #
      # # Long-running script (10 minutes):
      # migrate-data = {
      #   exec = "npm run migrate:production";
      #   description = "Run production data migration";
      #   timeout = 600;  # 10 minute timeout
      # };
      #
      # # Script with no timeout (not recommended):
      # interactive-shell = {
      #   exec = "bash";
      #   description = "Open interactive bash shell";
      #   timeout = 0;  # No timeout - use with caution
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    # Argument documentation for scripts
    ScriptArg = proto.mkMessage {
      name = "ScriptArg";
      description = ''
        Documentation for a script argument.

        Arguments are purely for documentation purposes - they describe what
        positional or named arguments the script accepts. The script itself
        is responsible for parsing these arguments.
      '';
      fields = {
        name = proto.string 1 "Argument name (e.g., 'file', '--output', '-v')";
        description = proto.optional (proto.string 2 "Human-readable description of the argument");
        required = proto.optional (proto.bool 3 "Whether the argument is required (default: false)");
        default = proto.optional (proto.string 4 "Default value if not provided");
      };
    };

    Script = proto.mkMessage {
      name = "Script";
      description = ''
        A development shell script definition.

        Scripts are compiled to Nix derivations via writeShellApplication and
        bundled into a single package with all scripts in bin/. The script
        name (attribute key) becomes the command name.

        Scripts are simpler than tasks - they don't have build dependencies,
        caching, or pipeline integration. Use them for ad-hoc utilities like
        `db-seed`, `format`, or `generate-types`.
      '';
      fields = {
        # Input options (for defining scripts in Nix)
        exec = proto.optional (proto.string 1 "Shell command to execute (mutually exclusive with path)");
        description = proto.optional (proto.string 2 "Human-readable description of the script");
        env = proto.map "string" "string" 3 "Environment variables to set when running the script";
        args = proto.repeated (proto.message "ScriptArg" 6 "Documented arguments for this script");
        timeout = proto.optional (proto.int32 7 "Maximum execution time in seconds (0 = no timeout, default: 300)");

        # Output options (serialized to agent - agent executes binPath directly)
        bin_path = proto.optional (proto.string 4 "Path to script executable in Nix store (computed)");
        source = proto.optional (proto.string 5 "Source type: inline or path (for debugging)");

        # Note: path and runtimeInputs are Nix-only (path type, packages), not in proto
      };
    };

    Scripts = proto.mkMessage {
      name = "Scripts";
      description = "Collection of development shell scripts";
      fields = {
        scripts = proto.map "string" "Script" 1 "Map of script name to script config";
      };
    };

    ScriptsConfig = proto.mkMessage {
      name = "ScriptsConfig";
      description = "Configuration for scripts package generation";
      fields = {
        enable = proto.bool 1 "Whether to add the scripts package to the devshell";
      };
    };
  };
}
