#!/usr/bin/env bash
# ==============================================================================
# common.sh - Shared functions for stackpanel entrypoints
#
# This library provides:
#   - Logging utilities (log_info, log_error, log_debug, log_warn)
#   - Project root detection (find_project_root)
#   - Auto-sources devshell.sh and secrets.sh
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Logging
# ==============================================================================

# ANSI colors (disabled if not in terminal)
if [[ -t 2 ]]; then
  _RED='\033[0;31m'
  _GREEN='\033[0;32m'
  _YELLOW='\033[0;33m'
  _BLUE='\033[0;34m'
  _NC='\033[0m' # No Color
else
  _RED=''
  _GREEN=''
  _YELLOW=''
  _BLUE=''
  _NC=''
fi

log_info() {
  echo -e "${_GREEN}[INFO]${_NC} $*" >&2
}

log_error() {
  echo -e "${_RED}[ERROR]${_NC} $*" >&2
}

log_warn() {
  echo -e "${_YELLOW}[WARN]${_NC} $*" >&2
}

log_debug() {
  if [[ "${DEBUG:-}" == "1" ]] || [[ "${STACKPANEL_DEBUG:-}" == "1" ]]; then
    echo -e "${_BLUE}[DEBUG]${_NC} $*" >&2
  fi
}

# ==============================================================================
# Project Root Detection
# ==============================================================================

# Find the project root (directory containing flake.nix)
# Usage: project_root=$(find_project_root)
find_project_root() {
  local dir="${1:-$(pwd)}"
  
  # First check STACKPANEL_ROOT env var
  if [[ -n "${STACKPANEL_ROOT:-}" ]] && [[ -d "$STACKPANEL_ROOT" ]]; then
    echo "$STACKPANEL_ROOT"
    return 0
  fi
  
  # Walk up directory tree looking for flake.nix
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/flake.nix" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  
  # Try git root as fallback
  if command -v git >/dev/null 2>&1; then
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_root" ]] && [[ -f "$git_root/flake.nix" ]]; then
      echo "$git_root"
      return 0
    fi
  fi
  
  return 1
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Die with error message
die() {
  log_error "$@"
  exit 1
}

# ==============================================================================
# Library Path Detection
# ==============================================================================

# Get the directory containing this script
_STACKPANEL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Source Other Libraries
# ==============================================================================

# Source devshell and secrets libraries
# These are sourced here so entrypoints only need to source common.sh

if [[ -f "$_STACKPANEL_LIB_DIR/devshell.sh" ]]; then
  # shellcheck source=devshell.sh
  source "$_STACKPANEL_LIB_DIR/devshell.sh"
fi

if [[ -f "$_STACKPANEL_LIB_DIR/secrets.sh" ]]; then
  # shellcheck source=secrets.sh
  source "$_STACKPANEL_LIB_DIR/secrets.sh"
fi
