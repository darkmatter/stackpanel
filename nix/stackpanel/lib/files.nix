# ==============================================================================
# files.nix
#
# Pure helper for building writer executables that materialize configured files
# into a target repository root. No flake-parts or perSystem dependency.
#
# This module creates shell scripts that can write multiple files atomically,
# useful for generating configuration files, build artifacts, or boilerplate.
#
# Usage:
#   let mk = import ./files.nix { inherit pkgs lib; };
#   in mk.mkWriter {
#     exeFilename = "write-files";
#     root = "/paath/to/repo";
#     runtimeRootVar = "STACKPANEL_ROOT";  # optional runtime override
#     files = [
#       { path = "README.md"; drv = pkgs.writeText "README.md" "hello\n"; }
#     ];
#   }
# ==============================================================================
{
  pkgs,
  lib,
}:
let
  types = lib.types;

  # ensure paths are safe to pass into shell
  q = lib.escapeShellArg;

  mkWriteSnippet =
    {
      path,
      drv,
    }:
    let
      # path relative to repo root
      rel = path;
    in
    ''
      # ${rel}
      mkdir -p "$(dirname ${q rel})"
      cat ${drv} > ${q rel}
    '';
in
{
  # mkWriter :: { exeFilename, root?, runtimeRootVar?, files } -> derivation (executable)
  mkWriter =
    {
      exeFilename ? "write-files",
      root ? null,
      runtimeRootVar ? null,
      files ? [ ],
    }:
    pkgs.writeShellApplication {
      name = exeFilename;

      # note: no git dependency; we cd into a provided root
      runtimeInputs = [ ];

      text = ''
        set -euo pipefail

        # Determine repo root
        ${lib.optionalString (runtimeRootVar != null) ''
          if [[ -n "''${${runtimeRootVar}:-}" ]]; then
            ROOT="''${${runtimeRootVar}}"
          else
            ROOT=${q (toString root)}
          fi
        ''}

        ${lib.optionalString (runtimeRootVar == null) ''
          ROOT=${q (toString root)}
        ''}

        if [[ -z "$ROOT" ]]; then
          echo "ERROR: repo root is empty" >&2
          exit 1
        fi

        cd "$ROOT"

        ${lib.concatLines (map mkWriteSnippet files)}

        echo "Wrote ${toString (builtins.length files)} file(s) to $ROOT"
      '';
    };
}
