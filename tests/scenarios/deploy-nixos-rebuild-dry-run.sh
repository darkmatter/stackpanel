#!/usr/bin/env bash
# ==============================================================================
# scenarios/deploy-nixos-rebuild-dry-run.sh
#
# Validates the nixos-rebuild deployment path by running
# `stackpanel deploy <app> --dry-run` for the first app configured with
# backend=nixos-rebuild. No actual remote deployment occurs.
#
# Usage:   bash tests/scenarios/deploy-nixos-rebuild-dry-run.sh
# Or via:  just test-scenario deploy-nixos-rebuild-dry-run
# ==============================================================================
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/lib/common.sh"
source "${REPO_ROOT}/tests/lib/deploy.sh"
source "${REPO_ROOT}/tests/lib/assert.sh"

log "[scenario] deploy-nixos-rebuild-dry-run"

# ── Validate tools ────────────────────────────────────────────────────────────
log "Validating required tools..."
require_command stackpanel "Build it first: cd apps/stackpanel-go && go build -o \$(go env GOPATH)/bin/stackpanel ."

# ── Find a configured nixos-rebuild app ───────────────────────────────────────
log "Discovering nixos-rebuild-backend apps via stackpanel deploy..."

APP_NAME="${STACKPANEL_NIXOS_REBUILD_TEST_APP:-}"
if [[ -z "${APP_NAME}" ]]; then
  DEPLOY_OUT="$(cd "${REPO_ROOT}" && stackpanel deploy 2>/dev/null || true)"
  APP_NAME="$(printf '%s\n' "${DEPLOY_OUT}" \
    | awk '/backend: nixos-rebuild/{found=1; next} found && /^  [a-z]/{print $1; exit}')" || true
fi

if [[ -z "${APP_NAME}" ]]; then
  warn "No nixos-rebuild-backend app found or STACKPANEL_NIXOS_REBUILD_TEST_APP not set."
  warn "Configure an app with deployment.backend = \"nixos-rebuild\" in config.nix."
  warn "Skipping scenario (not a failure — scenario is a no-op when no nixos-rebuild app is configured)."
  exit 0
fi

ok "Testing nixos-rebuild deploy dry-run for app: ${APP_NAME}"

# ── Run deploy --dry-run ──────────────────────────────────────────────────────
run_stackpanel_deploy "${APP_NAME}" dry-run
