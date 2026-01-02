#!/usr/bin/env bash
# syntax: bash
#
# Development shell loader
#
# Loader for IDEs like VS Code to start a shell inside a Nix-based development environment.
# Handles common edge cases like Nix not being in PATH yet.
#
# Shell mode: stackpanel
# Lookup file: devenv.yaml
#

export DIRENV_DISABLE=1

# --- small helpers
die() { printf "devshell: %s\n" "$*" >&2; exit 1; }

# Ensure nix is available
if ! command -v nix >/dev/null 2>&1; then
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
elif [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
  elif [[ -e /etc/profile.d/nix.sh ]]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/nix.sh
  fi
fi
command -v nix >/dev/null 2>&1 || die "nix not found, install it: https://install.determinate.systems"

# Find the right project root
find_root() {
if [[ -n "${STACKPANEL_ROOT:-}" ]]; then
    printf "%s
" "$STACKPANEL_ROOT"
    return 0
  fi
  # Prefer git root if available
  if command -v git >/dev/null 2>&1; then
    local gr
gr="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$gr" && -f "$gr/devenv.yaml" ]]; then
printf "%s\n" "$gr"
      return 0
    fi
  fi

  # Walk up from current dir
local d="$PWD"
while [[ "$d" != "/" ]]; do
if [[ -f "$d/devenv.yaml" ]]; then
printf "%s\n" "$d"
      return 0
    fi
d="$(dirname "$d")"
  done

die "couldn't find devenv.yaml (open VS Code at the repo root)"
}

ROOT="$(find_root)"
cd "$ROOT"

. <(devenv print-dev-env --impure