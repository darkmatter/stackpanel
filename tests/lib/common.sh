#!/usr/bin/env bash
# ==============================================================================
# tests/lib/common.sh — shared strict-mode setup, logging, and cleanup registry
#
# Source this file at the top of every test/scenario script:
#
#   REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
#   source "${REPO_ROOT}/tests/lib/common.sh"
#
# What this provides:
#   - set -euo pipefail
#   - REPO_ROOT detection (skips if already set by caller)
#   - Colour variables: RED GREEN YELLOW BLUE BOLD NC
#   - Logging helpers: log ok warn info die
#   - require_command <cmd> [hint]
#   - register_cleanup <cmd> / run_cleanups   (LIFO cleanup registry)
# ==============================================================================

set -euo pipefail

# ── Repo root detection ─────────────────────────────────────────────────────────
# Allow callers to pre-set REPO_ROOT before sourcing (recommended).
# When not set, compute from this file's location: tests/lib/../../ = repo root.
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export REPO_ROOT

# ── Colour variables ────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

export RED GREEN YELLOW BLUE BOLD NC

# ── Logging helpers ─────────────────────────────────────────────────────────────

log()  { printf "${BLUE}${BOLD}==>%s${NC} %s\n" "" "$*"; }
ok()   { printf "${GREEN}    ✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}    ⚠${NC} %s\n" "$*"; }
info() { printf "    %s\n" "$*"; }
die()  { printf "${RED}    ✗ FATAL:${NC} %s\n" "$*" >&2; exit 1; }

export -f log ok warn info die

# ── Tool requirement helper ─────────────────────────────────────────────────────
# require_command <cmd> [hint]
# Prints a friendly error and exits if <cmd> is not in PATH.
require_command() {
  local cmd="$1"
  local hint="${2:-Run inside the devshell: nix develop --impure}"
  if ! command -v "${cmd}" &>/dev/null; then
    die "${cmd} not found. ${hint}"
  fi
  ok "${cmd} found: $(command -v "${cmd}")"
}

export -f require_command

# ── Cleanup registry ────────────────────────────────────────────────────────────
# Commands are stored in _CLEANUP_CMDS[] and run in LIFO order by run_cleanups().
#
# Usage:
#   register_cleanup "hcloud server delete ${SERVER_ID}"
#   register_cleanup "rm -rf ${TMPDIR}"
#   trap run_cleanups EXIT

_CLEANUP_CMDS=()

register_cleanup() {
  _CLEANUP_CMDS+=("$1")
}

run_cleanups() {
  local exit_code=$?
  local i
  for (( i=${#_CLEANUP_CMDS[@]}-1; i>=0; i-- )); do
    local cmd="${_CLEANUP_CMDS[$i]}"
    # Best-effort: log failures but do not abort remaining cleanup steps
    eval "${cmd}" 2>/dev/null || warn "Cleanup step failed (ignored): ${cmd}"
  done
  if [[ ${exit_code} -eq 0 ]]; then
    printf "\n${GREEN}${BOLD}Test passed.${NC}\n"
  else
    printf "\n${RED}${BOLD}Test FAILED (exit code ${exit_code}).${NC}\n" >&2
  fi
}

export -f register_cleanup run_cleanups
