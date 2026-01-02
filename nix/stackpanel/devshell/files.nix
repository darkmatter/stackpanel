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
#   stackpanel.files.enable = true;  # default
#   stackpanel.files.entries.".github/workflows/ci.yml" = {
#     type = "text";
#     text = "name: CI\n...";
#   };
#   stackpanel.files.entries."scripts/deploy.sh" = {
#     type = "derivation";
#     drv = pkgs.writeScript "deploy" "#!/bin/bash\n...";
#     mode = "0755";
#   };
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.files;

  # Import util for debug logging
  util = import ../lib/util.nix { inherit pkgs lib config; };

  q = lib.escapeShellArg;

  # Filter to only enabled files
  enabledFiles = cfg.entries;

  # Check if there are any files to write (and global enable is true)
  hasFiles = enabledFiles != { };

  fileCount = builtins.length (builtins.attrNames enabledFiles);

  mkWriteSnippet =
    path: fileConfig:
    let
      mode = fileConfig.mode;
      # Get the source content based on type
      source =
        if fileConfig.type == "text" then
          pkgs.writeText (builtins.baseNameOf path) fileConfig.text
        else
          fileConfig.drv;
    in
    ''
      ${util.log.debug "files: writing ${path}"}
      echo "• ${path}"
      mkdir -p "$(dirname ${q path})"
      cat ${source} > ${q path}
      ${lib.optionalString (mode != null) ''
        ${util.log.debug "files: setting mode ${mode} on ${path}"}
        chmod ${q mode} ${q path}
      ''}
    '';

  writerDrv = pkgs.writeShellApplication {
    name = "write-files";
    runtimeInputs = [ pkgs.gum ];
    text = ''
      set -euo pipefail
      ${util.log.debug "files: starting file generation"}

      # Determine repo root
      ROOT="''${STACKPANEL_ROOT:-}"
      if [[ -z "$ROOT" ]]; then
        echo "ERROR: STACKPANEL_ROOT is not set. (Stackpanel core should set it.)" >&2
        exit 1
      fi

      ${util.log.debug "files: ROOT=$ROOT"}
      cd "$ROOT"

      ${lib.concatLines (lib.mapAttrsToList mkWriteSnippet enabledFiles)}

      ${util.log.debug "files: completed writing ${toString fileCount} file(s)"}
      echo "✅ wrote ${toString fileCount} file(s) into $ROOT"
    '';
  };
in
{
  imports = [
    ../core/options
  ];

  config = lib.mkIf hasFiles {
    # Make the executable available in PATH
    stackpanel.devshell.packages = [ writerDrv ];

    # Run write-files on shell entry (after core setup which sets STACKPANEL_ROOT)
    stackpanel.devshell.hooks.main = [
      ''
        ${util.log.debug "files: invoking write-files on shell entry"}
        ${writerDrv}/bin/write-files
      ''
    ];

    # Also expose as a devshell command (nice for devenv scripts, too)
    stackpanel.devshell.commands."write-files" = {
      exec = ''${writerDrv}/bin/write-files "$@"'';
      runtimeInputs = [ ];
      env = { };
    };
  };
}
