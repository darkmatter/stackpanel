#!/usr/bin/env bash
# ==============================================================================
# scenarios/provision-hetzner-setup-check.sh
#
# Validates all prerequisites and SOPS/hcloud token access for Hetzner
# provision tests without creating any cloud resources.
#
# Usage:   bash tests/scenarios/provision-hetzner-setup-check.sh
# Or via:  just test-scenario provision-hetzner-setup-check
# ==============================================================================
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/lib/common.sh"
source "${REPO_ROOT}/tests/lib/sops.sh"

SHARED_SECRETS="${REPO_ROOT}/.stack/secrets/vars/shared.sops.yaml"

log "[scenario] provision-hetzner-setup-check"

# ── Validate tools ────────────────────────────────────────────────────────────
log "Validating required tools..."
require_command hcloud
require_command jq
require_command ssh
require_command ssh-keygen
require_command nc
require_command stackpanel "Build it first: cd apps/stackpanel-go && go build -o \$(go env GOPATH)/bin/stackpanel ."

# ── Validate SOPS secrets file ────────────────────────────────────────────────
log "Validating SOPS secrets file..."
validate_sops_file "${SHARED_SECRETS}"

# ── Load and validate hcloud token ────────────────────────────────────────────
log "Loading HCLOUD_TOKEN from SOPS (key: hetzner_api_key)..."
sops_load_key "${SHARED_SECRETS}" hetzner_api_key HCLOUD_TOKEN

log "Validating HCLOUD_TOKEN against Hetzner API..."
if ! hcloud server-type list >/dev/null 2>&1; then
  die "HCLOUD_TOKEN appears invalid — Hetzner API rejected it."
fi
ok "HCLOUD_TOKEN validated against Hetzner API"

printf "\n${GREEN}${BOLD}Setup check passed.${NC} All prerequisites are met.\n"
printf "Run 'just test-scenario provision-hetzner-dry-run' to create an ephemeral server.\n"
