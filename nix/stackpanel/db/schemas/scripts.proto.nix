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
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
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
        exec = proto.string 1 "Shell command to execute";
        description = proto.optional (proto.string 2 "Human-readable description of the script");
        env = proto.map "string" "string" 3 "Environment variables to set when running the script";
        # Note: runtimeInputs is Nix-only (packages), not serializable to proto
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
