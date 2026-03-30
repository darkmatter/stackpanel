#!/usr/bin/env bash
# ==============================================================================
# scenarios/deploy-alchemy-smoke.sh
#
# Smoke test for the Alchemy (Cloudflare Workers) deployment path.
# Validates that the alchemy entrypoint exists and `stackpanel deploy <app>
# --dry-run` exits cleanly for a configured alchemy-backend app.
# No actual Cloudflare deployment occurs.
#
# Usage:   bash tests/scenarios/deploy-alchemy-smoke.sh
# Or via:  just test-scenario deploy-alchemy-smoke
# ==============================================================================
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/lib/common.sh"
source "${REPO_ROOT}/tests/lib/deploy.sh"
source "${REPO_ROOT}/tests/lib/assert.sh"

log "[scenario] deploy-alchemy-smoke"

# ── Validate tools ────────────────────────────────────────────────────────────
log "Validating required tools..."
require_command stackpanel "Build it first: cd apps/stackpanel-go && go build -o \$(go env GOPATH)/bin/stackpanel ."
require_command bun        "Install bun or ensure it is in PATH: https://bun.sh"

# ── Validate alchemy entrypoint ───────────────────────────────────────────────
ALCHEMY_ENTRY="${STACKPANEL_ALCHEMY_ENTRY:-${REPO_ROOT}/alchemy.run.ts}"
if [[ ! -f "${ALCHEMY_ENTRY}" ]]; then
  ALCHEMY_ENTRY="${REPO_ROOT}/infra/alchemy.ts"
fi
if [[ ! -f "${ALCHEMY_ENTRY}" ]]; then
  warn "Alchemy entrypoint not found at alchemy.run.ts or infra/alchemy.ts."
  warn "Set STACKPANEL_ALCHEMY_ENTRY to override the search path."
  warn "Skipping scenario (not a failure — scenario is a no-op when no entrypoint is present)."
  exit 0
fi
ok "Alchemy entrypoint found: ${ALCHEMY_ENTRY}"

# ── Find a configured alchemy app ─────────────────────────────────────────────
log "Discovering alchemy-backend apps via stackpanel deploy..."

APP_NAME="${STACKPANEL_ALCHEMY_TEST_APP:-}"
if [[ -z "${APP_NAME}" ]]; then
  DEPLOY_OUT="$(cd "${REPO_ROOT}" && stackpanel deploy 2>/dev/null || true)"
  APP_NAME="$(printf '%s\n' "${DEPLOY_OUT}" \
    | awk '/backend: alchemy/{found=1; next} found && /^  [a-z]/{print $1; exit}')" || true
fi

if [[ -z "${APP_NAME}" ]]; then
  warn "No alchemy-backend app found or STACKPANEL_ALCHEMY_TEST_APP not set."
  warn "Configure an app with deployment.backend = \"alchemy\" in config.nix."
  warn "Skipping scenario (not a failure — scenario is a no-op when no alchemy app is configured)."
  exit 0
fi

ok "Testing alchemy deploy dry-run for app: ${APP_NAME}"

# ── Run deploy --dry-run ──────────────────────────────────────────────────────
run_stackpanel_deploy "${APP_NAME}" dry-run
