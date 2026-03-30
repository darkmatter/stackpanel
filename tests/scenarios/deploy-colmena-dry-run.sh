#!/usr/bin/env bash
# ==============================================================================
# scenarios/deploy-colmena-dry-run.sh
#
# Validates the colmena deployment path by running `stackpanel deploy <app>
# --dry-run` for the first app configured with backend=colmena. No actual
# remote deployment occurs.
#
# Usage:   bash tests/scenarios/deploy-colmena-dry-run.sh
# Or via:  just test-scenario deploy-colmena-dry-run
# ==============================================================================
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/lib/common.sh"
source "${REPO_ROOT}/tests/lib/deploy.sh"
source "${REPO_ROOT}/tests/lib/assert.sh"

log "[scenario] deploy-colmena-dry-run"

# ── Validate tools ────────────────────────────────────────────────────────────
log "Validating required tools..."
require_command stackpanel "Build it first: cd apps/stackpanel-go && go build -o \$(go env GOPATH)/bin/stackpanel ."

if ! command -v colmena &>/dev/null; then
  warn "colmena not found. Add colmena to devshell packages: nix profile install nixpkgs#colmena"
  warn "Skipping scenario (not a failure — colmena is optional for non-NixOS deploy environments)."
  exit 0
fi
ok "colmena found: $(command -v colmena)"

# ── Find a configured colmena app from deployment listing ────────────────────
log "Discovering colmena-backend apps via stackpanel deploy..."
(cd "${REPO_ROOT}" && stackpanel deploy) 2>/dev/null || true

APP_NAME="${STACKPANEL_COLMENA_TEST_APP:-}"
if [[ -z "${APP_NAME}" ]]; then
  # Try to auto-detect from deploy listing output: look for backend: colmena
  DEPLOY_OUT="$(cd "${REPO_ROOT}" && stackpanel deploy 2>/dev/null || true)"
  # Extract the first app that follows a colmena backend annotation
  APP_NAME="$(printf '%s\n' "${DEPLOY_OUT}" \
    | awk '/backend: colmena/{found=1; next} found && /^  [a-z]/{print $1; exit}')" || true
fi

if [[ -z "${APP_NAME}" ]]; then
  warn "No colmena-backend app found or STACKPANEL_COLMENA_TEST_APP not set."
  warn "Configure an app with deployment.backend = \"colmena\" and deployment.targets in config.nix."
  warn "Skipping scenario (not a failure — scenario is a no-op when no colmena app is configured)."
  exit 0
fi

ok "Testing colmena deploy dry-run for app: ${APP_NAME}"

# ── Run deploy --dry-run ──────────────────────────────────────────────────────
run_stackpanel_deploy "${APP_NAME}" dry-run
