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
#
# Usage:
#   stackpanel.scripts.db-seed = {
#     exec = "npm run seed";
#     description = "Seed the database with test data";
#   };
#   stackpanel.scripts."api:start" = {
#     exec = "bun run dev";
#     runtimeInputs = [ pkgs.bun ];
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

  # Build a single script executable
  mkScript =
    name: script:
    let
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''export ${k}=${lib.escapeShellArg v}'') (script.env or { })
      );
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = script.runtimeInputs or [ ];
      text = ''
        set -euo pipefail
        ${envExports}
        ${script.exec}
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

  # Generate serializable script definitions for CLI access
  serializableScripts = lib.mapAttrs (name: script: {
    inherit name;
    exec = script.exec;
    description = script.description or null;
    env = script.env or { };
  }) cfg;

  hasScripts = cfg != { };

  # Nix-only script options (not serializable to proto - contains packages)
  nixScriptOptionsModule =
    { lib, ... }:
    {
      options = {
        runtimeInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = ''
            (Nix extension) Packages to include in PATH when running the script.
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
          { options = db.extend.script; }
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

      Proto-derived options (from scripts.proto.nix):
        - exec: Shell command to execute
        - description: Human-readable description
        - env: Environment variables

      Nix extensions:
        - runtimeInputs: Nix packages for PATH
      
      Example:
        stackpanel.scripts.db-seed = {
          exec = "npm run seed";
          description = "Seed the database";
        };
    '';
    example = lib.literalExpression ''
      {
        db-seed = {
          exec = "npm run seed";
          description = "Seed the database with test data";
        };
        "api:start" = {
          exec = "bun run dev";
          runtimeInputs = [ pkgs.bun ];
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
      description = "The generated scripts package (read-only).";
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
