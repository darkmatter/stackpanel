#!/usr/bin/env bash
# ==============================================================================
# devshell.sh - Devshell detection and auto-entry for stackpanel entrypoints
#
# This library provides functions to:
#   - Detect if currently in a Nix devshell
#   - Auto-source the devshell environment via `nix print-dev-env`
# ==============================================================================

# ==============================================================================
# Devshell Detection
# ==============================================================================

in_devshell() {
  if [[ -n "${STACKPANEL_ROOT:-}" ]]; then
    return 0
  fi

  if [[ -n "${IN_NIX_SHELL:-}" ]]; then
    return 0
  fi

  if [[ -n "${STACKPANEL_DEVSHELL:-}" ]]; then
    return 0
  fi

  return 1
}

# ==============================================================================
# Devshell Auto-Entry
# ==============================================================================

ensure_devshell() {
  if in_devshell; then
    log_debug "Already in devshell"
    return 0
  fi

  log_info "Not in devshell, sourcing Nix environment..."

  local project_root
  if ! project_root=$(find_project_root); then
    log_error "Could not find project root (flake.nix)"
    log_error "Please run from within a stackpanel project or enter the devshell manually:"
    log_error "  direnv allow"
    log_error "  # or"
    log_error "  nix develop"
    return 1
  fi

  log_debug "Project root: $project_root"
  cd "$project_root" || return 1

  if ! command_exists nix; then
    log_error "nix command not found"
    log_error "Please install Nix or enter the devshell manually:"
    log_error "  https://nixos.org/download.html"
    return 1
  fi

  log_debug "Running: nix print-dev-env"

  local dev_env
  if dev_env=$(nix print-dev-env 2>/dev/null); then
    eval "$dev_env"
    export STACKPANEL_DEVSHELL=1
    log_info "Devshell environment sourced"
    return 0
  else
    log_error "Failed to source devshell environment"
    log_error "Try entering the devshell manually:"
    log_error "  nix develop"
    return 1
  fi
}

# ==============================================================================
# Devshell Environment Caching (optional optimization)
# ==============================================================================

cache_devshell_env() {
  local cache_file="${1:-.stack/state/dev-env.sh}"
  local project_root

  if ! project_root=$(find_project_root); then
    log_error "Could not find project root"
    return 1
  fi

  local full_cache_path="$project_root/$cache_file"
  local cache_dir
  cache_dir=$(dirname "$full_cache_path")

  mkdir -p "$cache_dir"

  log_info "Caching devshell environment to $cache_file..."

  cd "$project_root" || return 1

  if nix print-dev-env > "$full_cache_path" 2>/dev/null; then
    log_info "Devshell environment cached"
    return 0
  else
    log_error "Failed to cache devshell environment"
    return 1
  fi
}

load_cached_devshell_env() {
  local cache_file="${1:-.stack/state/dev-env.sh}"
  local max_age="${2:-3600}"
  local project_root

  if ! project_root=$(find_project_root); then
    return 1
  fi

  local full_cache_path="$project_root/$cache_file"

  if [[ ! -f "$full_cache_path" ]]; then
    log_debug "No cached devshell environment found"
    return 1
  fi

  local cache_mtime
  cache_mtime=$(stat -c %Y "$full_cache_path" 2>/dev/null || stat -f %m "$full_cache_path" 2>/dev/null)
  local current_time
  current_time=$(date +%s)
  local age=$((current_time - cache_mtime))

  if [[ $age -gt $max_age ]]; then
    log_debug "Cached devshell environment is stale ($age seconds old)"
    return 1
  fi

  log_debug "Loading cached devshell environment ($age seconds old)"

  # shellcheck disable=SC1090
  source "$full_cache_path"
  export STACKPANEL_DEVSHELL=1

  log_info "Devshell environment loaded from cache"
  return 0
}

ensure_devshell_cached() {
  if in_devshell; then
    log_debug "Already in devshell"
    return 0
  fi

  local cache_file="${1:-.stack/state/dev-env.sh}"
  local max_age="${2:-3600}"

  if load_cached_devshell_env "$cache_file" "$max_age"; then
    return 0
  fi

  if ensure_devshell; then
    (cache_devshell_env "$cache_file" &) 2>/dev/null
    return 0
  fi

  return 1
}
