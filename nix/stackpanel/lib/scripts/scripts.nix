# attrset of useful scripts
{
  pkgs,
  lib,
  inputs,
  system,
  ...
}:
let
  multisops = pkgs.writeShellApplication {
    name = "multisops";
    runtimeInputs = with pkgs; [
      sops
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      local files=()
      local cmd=()

      # Parse args until --
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --)
            shift
            break
            ;;
          *)
            files+=("$1")
            shift
            ;;
        esac
      done

      if [[ ''${#files[@]} -eq 0 ]]; then
        echo "error: no sops files provided" >&2
        return 1
      fi

      if [[ $# -eq 0 ]]; then
        echo "error: no command provided after --" >&2
        return 1
      fi

      cmd=("$@")

      # Build nested sops exec-env chain
      local wrapped_cmd
      wrapped_cmd="$(printf '%q ' "''${cmd[@]}")"

      for ((i=''${#files[@]}-1; i>=0; i--)); do
        wrapped_cmd="sops exec-env ''${files[i]} -- $wrapped_cmd"
      done

      eval "$wrapped_cmd"
    '';
  };
in
{
  devenv-scripts-stackpanel = pkgs.stdenv.mkDerivation {
    pname = "stackpanel-scripts";
    version = "0.1.0";
    src = null;
    buildInputs = [
      pkgs.bashInteractive
      multisops
    ];
    buildCommand = ''
      mkdir -p $out/bin
      cp ${inputs.devenv.packages.${system}.devenv-scripts-stackpanel}/bin/stackpanel_* $out/bin/
    '';
    # No need for any special runtime dependencies
    passthru = { };
  };
}
