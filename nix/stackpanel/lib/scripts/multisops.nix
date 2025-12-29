{ pkgs, path, ... }:
 pkgs.writeShellApplication {
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
  }