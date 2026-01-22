#!/usr/bin/env bash
# ==============================================================================
# devshell.sh - Devshell detection and auto-entry for stackpanel entrypoints
#
# This library provides functions to:
#   - Detect if currently in a Nix devshell
#   - Auto-source the devshell environment via `nix print-dev-env`
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#   ensure_devshell  # Will source devshell if not already in one
# ==============================================================================

# ==============================================================================
# Devshell Detection
# ==============================================================================

# Check if currently in a Nix devshell
# Returns 0 if in devshell, 1 otherwise
in_devshell() {
  # Check standard Nix shell indicator
  if [[ -n "${IN_NIX_SHELL:-}" ]]; then
    return 0
  fi
  
  # Check devenv indicator
  if [[ -n "${DEVENV_ROOT:-}" ]]; then
    return 0
  fi
  
  # Check stackpanel indicator
  if [[ -n "${STACKPANEL_DEVSHELL:-}" ]]; then
    return 0
  fi
  
  return 1
}

# ==============================================================================
# Devshell Auto-Entry
# ==============================================================================

# Ensure we're in the devshell, auto-source if not
# Usage: ensure_devshell
ensure_devshell() {
  if in_devshell; then
    log_debug "Already in devshell"
    return 0
  fi
  
  log_info "Not in devshell, sourcing Nix environment..."
  
  # Find project root
  local project_root
  if ! project_root=$(find_project_root); then
    log_error "Could not find project root (flake.nix)"
    log_error "Please run from within a stackpanel project or enter the devshell manually:"
    log_error "  direnv allow"
    log_error "  # or"
    log_error "  nix develop --impure"
    return 1
  fi
  
  log_debug "Project root: $project_root"
  
  # Change to project root for nix commands
  cd "$project_root" || return 1
  
  # Check if nix is available
  if ! command_exists nix; then
    log_error "nix command not found"
    log_error "Please install Nix or enter the devshell manually:"
    log_error "  https://nixos.org/download.html"
    return 1
  fi
  
  # Use nix print-dev-env to get environment without entering subshell
  log_debug "Running: nix print-dev-env --impure"
  
  local dev_env
  if dev_env=$(nix print-dev-env --impure 2>/dev/null); then
    # Source the environment
    eval "$dev_env"
    
    # Set indicator that we sourced the devshell
    export STACKPANEL_DEVSHELL=1
    
    log_info "Devshell environment sourced"
    return 0
  else
    log_error "Failed to source devshell environment"
    log_error "Try entering the devshell manually:"
    log_error "  nix develop --impure"
    return 1
  fi
}

# ==============================================================================
# Devshell Environment Caching (optional optimization)
# ==============================================================================

# Cache the devshell environment to a file for faster subsequent loads
# Usage: cache_devshell_env <cache_file>
cache_devshell_env() {
  local cache_file="${1:-.stackpanel/state/dev-env.sh}"
  local project_root
  
  if ! project_root=$(find_project_root); then
    log_error "Could not find project root"
    return 1
  fi
  
  local full_cache_path="$project_root/$cache_file"
  local cache_dir
  cache_dir=$(dirname "$full_cache_path")
  
  # Ensure cache directory exists
  mkdir -p "$cache_dir"
  
  log_info "Caching devshell environment to $cache_file..."
  
  cd "$project_root" || return 1
  
  if nix print-dev-env --impure > "$full_cache_path" 2>/dev/null; then
    log_info "Devshell environment cached"
    return 0
  else
    log_error "Failed to cache devshell environment"
    return 1
  fi
}

# Load devshell from cache if available and fresh
# Usage: load_cached_devshell_env <cache_file> <max_age_seconds>
load_cached_devshell_env() {
  local cache_file="${1:-.stackpanel/state/dev-env.sh}"
  local max_age="${2:-3600}"  # Default: 1 hour
  local project_root
  
  if ! project_root=$(find_project_root); then
    return 1
  fi
  
  local full_cache_path="$project_root/$cache_file"
  
  # Check if cache exists
  if [[ ! -f "$full_cache_path" ]]; then
    log_debug "No cached devshell environment found"
    return 1
  fi
  
  # Check cache age
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
  
  # Source the cached environment
  # shellcheck disable=SC1090
  source "$full_cache_path"
  export STACKPANEL_DEVSHELL=1
  
  log_info "Devshell environment loaded from cache"
  return 0
}

# Ensure devshell with caching support
# Usage: ensure_devshell_cached [cache_file] [max_age_seconds]
ensure_devshell_cached() {
  if in_devshell; then
    log_debug "Already in devshell"
    return 0
  fi
  
  local cache_file="${1:-.stackpanel/state/dev-env.sh}"
  local max_age="${2:-3600}"
  
  # Try loading from cache first
  if load_cached_devshell_env "$cache_file" "$max_age"; then
    return 0
  fi
  
  # Fall back to fresh evaluation
  if ensure_devshell; then
    # Cache for next time (in background to not slow down current run)
    (cache_devshell_env "$cache_file" &) 2>/dev/null
    return 0
  fi
  
  return 1
}
