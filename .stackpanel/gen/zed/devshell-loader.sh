#!/usr/bin/env bash
# syntax: bash
#
# Development shell loader
#
# Loader for IDEs like VS Code to start a shell inside a Nix-based development environment.
# Handles common edge cases like Nix not being in PATH yet.
#
# Shell mode: stackpanel
# Lookup file: .git
#


# --- small helpers
die() { printf "devshell: %s\\n" "$*" >&2; exit 1; }

# Avoid recursion if VS Code reuses this profile inside itself
if [[ "${DEVENV_VSCODE_SHELL:-}" == "1" ]]; then
  # If we're already inside, just start a login shell.
  exec "${SHELL:-/bin/bash}" -l
fi
export DEVENV_VSCODE_SHELL=1

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
    printf "%s\\n" "$STACKPANEL_ROOT"
    return 0
  fi
  # Prefer git root if available
  if command -v git >/dev/null 2>&1; then
    local gr
gr="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$gr" && -e "$gr/.git" ]]; then
printf "%s\\n" "$gr"
      return 0
    fi
  fi

  # Walk up from current dir
local d="$PWD"
while [[ "$d" != "/" ]]; do
if [[ -e "$d/.git" ]]; then
printf "%s\\n" "$d"
      return 0
    fi
d="$(dirname "$d")"
  done

die "couldn't find .git (open VS Code at the repo root)"
}

ROOT="$(find_root)"
cd "$ROOT"

_sp_compute_shell_hash() {
  local files=(
    "$ROOT/flake.nix"
    "$ROOT/flake.lock"
    "$ROOT/.stackpanel/config.nix"
    "$ROOT/devenv.nix"
    "$ROOT/devenv.yaml"
  )
  local hash_input=""
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      hash_input+="$(cat "$f" 2>/dev/null)"
    fi
  done
  echo -n "$hash_input" | md5sum | cut -d' ' -f1
}

_sp_cache_is_fresh() {
  local cache_file="$1"
  [[ -f "$cache_file" ]] || return 1

  # Extract hash from cache header (line 3: "# Shell hash: <hash>")
  local cached_hash
  cached_hash=$(sed -n '3s/^# Shell hash: //p' "$cache_file" 2>/dev/null)
  [[ -n "$cached_hash" ]] || return 1

  # Compare with current hash
  local current_hash
  current_hash=$(_sp_compute_shell_hash)
  [[ "$cached_hash" == "$current_hash" ]]
}


_sp_cached_env="$ROOT/.stackpanel/gen/nix-print-dev-env.sh"
if [[ -f "$_sp_cached_env" ]]; then
  if ! _sp_cache_is_fresh "$_sp_cached_env"; then
    echo "⚠️  devshell: cached env is stale (run 'nix develop --impure' to refresh)" >&2
  fi
  . "$_sp_cached_env"
else
  DEV_SCRIPT="$ROOT/devshell"

  if [[ -x "$DEV_SCRIPT" ]]; then
    exec "$DEV_SCRIPT"
  fi

  # Fallback: enter the devshell directly (runs hooks that materialize ./devshell)
  exec nix develop --impure
fi
