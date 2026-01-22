# ==============================================================================
# scripts.nix
#
# Unified script management for stackpanel devshells.
#
# This module consolidates script/command definitions into a single
# `stackpanel.scripts` option. All scripts are bundled into a single package
# with executables in `bin/`, avoiding conflicts and providing clean namespace.
#
# Schema defined in: nix/stackpanel/db/schemas/scripts.proto.nix
#
# Features:
#   - Attribute set keyed by command name (ensures no conflicts)
#   - Single package with all scripts in `bin/`
#   - Optional devshell integration (enabled by default)
#   - Support for runtimeInputs, env, and description
#   - Load script content from files via `path` option
#
# Usage (inline exec):
#   stackpanel.scripts.db-seed = {
#     exec = "npm run seed";
#     description = "Seed the database with test data";
#   };
#
# Usage (path to file):
#   stackpanel.scripts.db-seed = {
#     path = ./.stackpanel/src/scripts/db-seed.sh;
#     description = "Seed the database with test data";
#     runtimeInputs = [ pkgs.nodejs ];
#   };
#
# Extension scripts use namespace prefix:
#   stackpanel.scripts."sst:deploy" = {
#     path = ./src/scripts/deploy.sh;
#     description = "Deploy SST infrastructure";
#   };
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Import proto-derived options from db
  db = import ../db { inherit lib; };

  cfg = config.stackpanel.scripts;
  scriptsCfg = config.stackpanel.scriptsConfig;

  # Resolve script content from either exec or path
  resolveScriptContent = name: script:
    let
      hasExec = script.exec or null != null && script.exec != "";
      hasPath = script.path or null != null;
    in
    if hasExec && hasPath then
      throw "Script '${name}': cannot specify both 'exec' and 'path' - use one or the other"
    else if hasPath then
      builtins.readFile script.path
    else if hasExec then
      script.exec
    else
      throw "Script '${name}': must specify either 'exec' or 'path'";

  # Build a single script executable
  mkScript =
    name: script:
    let
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') (script.env or { })
      );
      scriptContent = resolveScriptContent name script;
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = script.runtimeInputs or [ ];
      text = ''
        set -euo pipefail
        ${envExports}
        ${scriptContent}
      '';
    };

  # Build all scripts as individual packages
  scriptPackages = lib.mapAttrs mkScript cfg;

  # Create a combined package with bin/ directory containing all scripts
  scriptsPackage = pkgs.symlinkJoin {
    name = "stackpanel-scripts";
    paths = lib.attrValues scriptPackages;
    meta = {
      description = "Stackpanel project scripts";
    };
  };

  # Generate serializable script definitions for CLI/agent access
  # Uses derivation paths instead of inline content for security
  serializableScripts = lib.mapAttrs (name: script:
    let
      pkg = scriptPackages.${name};
    in
    {
      inherit name;
      description = script.description or null;
      env = script.env or { };
      # Derivation path - agent executes this directly (no sh -c with inline content)
      binPath = "${pkg}/bin/${name}";
      # Source info for debugging
      source = if script.path or null != null then "path" else "inline";
    }
  ) cfg;

  hasScripts = cfg != { };

  # Nix-only script options (not serializable to proto - contains packages/paths)
  nixScriptOptionsModule =
    { lib, ... }:
    {
      options = {
        # Path is Nix-only because it uses types.path (not serializable as string)
        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to script file. Content is read and used as the script body.
            Mutually exclusive with `exec` - use one or the other.
          '';
          example = lib.literalExpression "./.stackpanel/src/scripts/my-script.sh";
        };

        runtimeInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = ''
            Packages to include in PATH when running the script.
            These are pinned to specific Nix store paths, ensuring reproducible execution.
          '';
          example = lib.literalExpression "[ pkgs.nodejs pkgs.jq ]";
        };
      };
    };
in
{
  options.stackpanel.scriptModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Additional modules to extend script configuration options.
    '';
  };

  options.stackpanel.scripts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [
          # Proto-derived options (exec, description, env)
          # Note: Strip the __db_extend_marker__ when using db.extend.* directly as options
          { options = removeAttrs db.extend.script [ "__db_extend_marker__" ]; }
          # Nix-only runtime options (runtimeInputs)
          nixScriptOptionsModule
        ]
        ++ config.stackpanel.scriptModules;
        specialArgs = { inherit lib; };
      }
    );
    default = { };
    description = ''
      Scripts exposed in the development shell.
      
      Each script becomes an executable command available in PATH.
      The attribute name determines the command name.

      Script content can be provided via:
        - exec: Inline shell command
        - path: Path to script file (content is read at eval time)

      These are mutually exclusive - use one or the other.

      Proto-derived options (from scripts.proto.nix):
        - exec: Shell command to execute
        - description: Human-readable description
        - env: Environment variables

      Nix extensions:
        - path: Path to script file (alternative to inline exec)
        - runtimeInputs: Nix packages for PATH

      Extension scripts should use namespace prefix (e.g., "sst:deploy").
    '';
    example = lib.literalExpression ''
      {
        # Inline exec
        db-seed = {
          exec = "npm run seed";
          description = "Seed the database with test data";
        };

        # Path to script file
        deploy = {
          path = ./.stackpanel/src/scripts/deploy.sh;
          description = "Deploy the application";
          runtimeInputs = [ pkgs.awscli2 ];
        };

        # Extension-namespaced script
        "sst:dev" = {
          exec = "sst dev";
          description = "Start SST dev mode";
          runtimeInputs = [ pkgs.nodejs ];
        };
      }
    '';
  };

  options.stackpanel.scriptsConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to add the scripts package to the devshell.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = scriptsPackage;
      description = "The generated combined scripts package (read-only).";
    };

    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      default = scriptPackages;
      description = ''
        Individual script packages (read-only).
        Use to reference specific scripts: config.stackpanel.scriptsConfig.packages.my-script
      '';
    };
  };

  config = lib.mkIf (hasScripts && scriptsCfg.enable) {
    # Add the scripts package to devshell
    stackpanel.devshell.packages = [ scriptsPackage ];

    # Store serializable definitions for CLI/TUI access
    stackpanel.devshell._commandsSerializable = serializableScripts;

    # Expose individual script packages as flake outputs
    # Available via: nix run .#scripts.<script-name>
    stackpanel.outputs.scripts = scriptPackages;

    # Also expose the combined package
    stackpanel.outputs.stackpanel-scripts = scriptsPackage;

    # Print available scripts on shell entry
    stackpanel.devshell.hooks.main = [
      ''
        echo "📜 stackpanel scripts loaded"
      ''
    ];
  };
}
