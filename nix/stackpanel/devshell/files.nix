# ==============================================================================
# files.nix
#
# File generation system for devshell environments.
#
# This module provides a declarative way to generate files in the project
# workspace. Files are written by a generated shell script that can be run
# manually or on shell entry. Supports custom file modes and automatic
# directory creation.
#
# Usage:
#   stackpanel.files = {
#     enable = true;
#     files = [{
#       path = "config.json";
#       drv = pkgs.writeText "config" (builtins.toJSON { ... });
#       mode = "644";
#     }];
#   };
# ==============================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.stackpanel.files;
  types = lib.types;

  q = lib.escapeShellArg;

  mkWriteSnippet = item:
    let
      path = item.path;
      drv = item.drv;
      mode = item.mode or null;
      # If you want “no leading whitespace” heredocs etc, do that in drv creation.
    in ''
      echo "• ${path}"
      mkdir -p "$(dirname ${q path})"
      cat ${drv} > ${q path}
      ${lib.optionalString (mode != null) ''
        chmod ${q mode} ${q path}
      ''}
    '';

  writerDrv =
    pkgs.writeShellApplication {
      name = cfg.exeFilename;
      runtimeInputs = [];
      text = ''
        set -euo pipefail

        # Determine repo root
        ROOT="''${${cfg.rootVar}:-}"
        if [[ -z "$ROOT" ]]; then
          echo "ERROR: ${cfg.rootVar} is not set. (Stackpanel core should set it.)" >&2
          exit 1
        fi

        cd "$ROOT"

        ${lib.concatLines (map mkWriteSnippet cfg.files)}

        echo "✅ wrote ${toString (builtins.length cfg.files)} file(s) into $ROOT"
      '';
    };
in
{
  imports = [
    ../core/options
  ];

  config = lib.mkIf cfg.enable {
    # Make the executable available in PATH
    stackpanel.devshell.packages = [ writerDrv ];

    # Also expose as a devshell command (nice for devenv scripts, too)
    stackpanel.devshell.commands.${cfg.exeFilename} = {
      exec = ''${writerDrv}/bin/${cfg.exeFilename} "$@"'';
      runtimeInputs = [];
      env = {};
    };
  };
}