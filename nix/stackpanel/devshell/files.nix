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

  # Import util for debug logging
  util = import ../lib/util.nix { inherit pkgs lib config; };

  q = lib.escapeShellArg;

  mkWriteSnippet = item:
    let
      path = item.path;
      drv = item.drv;
      mode = item.mode or null;
      # If you want “no leading whitespace” heredocs etc, do that in drv creation.
    in ''
      ${util.log.debug "files: writing ${path}"}
      echo "• ${path}"
      mkdir -p "$(dirname ${q path})"
      cat ${drv} > ${q path}
      ${lib.optionalString (mode != null) ''
        ${util.log.debug "files: setting mode ${mode} on ${path}"}
        chmod ${q mode} ${q path}
      ''}
    '';

  writerDrv =
    pkgs.writeShellApplication {
      name = cfg.exeFilename;
      runtimeInputs = [ pkgs.gum ];
      text = ''
        set -euo pipefail
        ${util.log.debug "files: starting file generation"}

        # Determine repo root
        ROOT="''${${cfg.rootVar}:-}"
        if [[ -z "$ROOT" ]]; then
          echo "ERROR: ${cfg.rootVar} is not set. (Stackpanel core should set it.)" >&2
          exit 1
        fi

        ${util.log.debug "files: ROOT=$ROOT"}
        cd "$ROOT"

        ${lib.concatLines (map mkWriteSnippet cfg.files)}

        ${util.log.debug "files: completed writing ${toString (builtins.length cfg.files)} file(s)"}
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