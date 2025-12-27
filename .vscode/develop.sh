#!/usr/bin/env bash

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"


# If invoked as a shell executable (VS Code shell task), convert the command string to bash -lc
if [[ ${1-} == "-lc" || ${1-} == "-c" ]]; then
    shift
    # Reconstruct the command string exactly as provided to the shell
    CMD="$*"
    # Run the command inside the current flake with a login-capable shell that parses the string
    exec nix develop "$ROOT" -c bash -lc "$CMD"
    exit 0
fi

# If no arguments are provided, run an interactive dev shell
if (($# == 0)); then
    # Interactive dev shell
    exec nix develop "$ROOT" -c bash -l
    exit 0
fi

# default
exec nix develop --impure "$ROOT" -c bash -c "$@"
