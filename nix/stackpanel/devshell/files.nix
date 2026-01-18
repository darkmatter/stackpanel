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
  util = config.stackpanel.util;

  q = lib.escapeShellArg;

  # Filter to only enabled files
  enabledFiles = cfg.entries;

  # Check if there are any files to write (and global enable is true)
  hasFiles = enabledFiles != { };

  fileCount = builtins.length (builtins.attrNames enabledFiles);

  manifestEntries = lib.mapAttrsToList (
    path: fileConfig: {
      inherit path;
      type = fileConfig.type or "text";
      mode = fileConfig.mode or null;
      source = fileConfig.source or null;
      description = fileConfig.description or null;
      target = fileConfig.target or null;
      storePath =
        if (fileConfig.type or "text") == "derivation" && fileConfig.drv != null then
          builtins.toString fileConfig.drv
        else
          null;
    }
  ) enabledFiles;

  manifestJson = builtins.toJSON {
    version = 1;
    files = manifestEntries;
  };

  mkWriteSnippet =
    path: fileConfig:
    let
      mode = fileConfig.mode;
      fileType = fileConfig.type;

      # Get the source content based on type
      source =
        if fileType == "text" then
          pkgs.writeText (builtins.baseNameOf path) fileConfig.text
        else if fileType == "derivation" then
          fileConfig.drv
        else
          null; # symlink doesn't use source

      # For symlinks, get the target
      symlinkTarget = fileConfig.target or null;
    in
    if fileType == "symlink" then
      ''
        ${util.log.debug "files: creating symlink ${path} -> ${symlinkTarget}"}
        echo "• ${path} -> ${symlinkTarget}"
        mkdir -p "$(dirname ${q path})"
        # Remove existing file/symlink if present
        rm -f ${q path} 2>/dev/null || true
        ln -s ${q symlinkTarget} ${q path}
      ''
    else
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

      STATE_DIR="''${STACKPANEL_STATE_DIR:-$ROOT/.stackpanel/state}"
      mkdir -p "$STATE_DIR"
      cat > "$STATE_DIR/files.json" << 'STACKPANEL_FILES_EOF'
      ${manifestJson}
      STACKPANEL_FILES_EOF

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
