#!/usr/bin/env bash
# ==============================================================================
# scenarios/provision-hetzner-dry-run.sh
#
# Creates an ephemeral Hetzner CX22 server, injects machine config, runs
# `stackpanel provision --dry-run`, verifies the command plan, then destroys
# the server.  Default/safe regression mode for CI.
#
# Usage:   bash tests/scenarios/provision-hetzner-dry-run.sh
# Or via:  just test-scenario provision-hetzner-dry-run
# ==============================================================================
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/lib/common.sh"
source "${REPO_ROOT}/tests/lib/sops.sh"
source "${REPO_ROOT}/tests/lib/hetzner.sh"
source "${REPO_ROOT}/tests/lib/ssh.sh"
source "${REPO_ROOT}/tests/lib/stackpanel_config.sh"
source "${REPO_ROOT}/tests/lib/deploy.sh"
source "${REPO_ROOT}/tests/lib/assert.sh"

trap run_cleanups EXIT

SHARED_SECRETS="${REPO_ROOT}/.stack/secrets/vars/shared.sops.yaml"
SUFFIX="$(date +%s)-$$"
HCLOUD_SERVER_NAME="stackpanel-e2e-${SUFFIX}"
HCLOUD_KEY_NAME="stackpanel-e2e-${SUFFIX}"
MACHINE_NAME="ephemeral-provision-test"
TMPDIR_SCENARIO="$(mktemp -d)"
SSH_KEY_FILE="${TMPDIR_SCENARIO}/id_ed25519"
CONFIG_LOCAL="${REPO_ROOT}/.stack/config.local.nix"
CONFIG_LOCAL_BAK="${REPO_ROOT}/.stack/config.local.nix.provision-e2e-bak"

SERVER_ID=""
KEY_ID=""

register_cleanup "rm -rf '${TMPDIR_SCENARIO}'"

log "[scenario] provision-hetzner-dry-run"

# ── Validate tools ────────────────────────────────────────────────────────────
log "Validating required tools..."
require_command hcloud
require_command jq
require_command ssh
require_command ssh-keygen
require_command nc
require_command stackpanel "Build it first: cd apps/stackpanel-go && go build -o \$(go env GOPATH)/bin/stackpanel ."

# ── Load HCLOUD_TOKEN ─────────────────────────────────────────────────────────
log "Loading HCLOUD_TOKEN from SOPS..."
validate_sops_file "${SHARED_SECRETS}"
sops_load_key "${SHARED_SECRETS}" hetzner_api_key HCLOUD_TOKEN
hetzner_validate_token

# ── Generate temporary SSH key ────────────────────────────────────────────────
log "Generating temporary SSH key pair..."
ssh-keygen -t ed25519 -f "${SSH_KEY_FILE}" -N "" -C "stackpanel-provision-e2e-${SUFFIX}" -q
TEMP_PUBKEY="$(cat "${SSH_KEY_FILE}.pub")"
ok "Generated ${SSH_KEY_FILE}"

# ── Register key + create server ─────────────────────────────────────────────
KEY_OUTPUT="$(hetzner_create_ssh_key "${HCLOUD_KEY_NAME}" "${SSH_KEY_FILE}.pub")"
KEY_ID="$(echo "${KEY_OUTPUT}" | jq -r '.id')"
ok "Registered SSH key (id: ${KEY_ID})"
register_cleanup "hetzner_delete_ssh_key '${KEY_ID}' '${HCLOUD_KEY_NAME}'"

SERVER_OUTPUT="$(hetzner_create_server "${HCLOUD_SERVER_NAME}" cx22 debian-12 fsn1 "${HCLOUD_KEY_NAME}")"
SERVER_ID="$(echo "${SERVER_OUTPUT}" | jq -r '.server.id')"
SERVER_IP="$(hetzner_server_ip "${SERVER_OUTPUT}")"
ok "Server created (id: ${SERVER_ID}, ip: ${SERVER_IP})"
register_cleanup "hetzner_delete_server '${SERVER_ID}' '${HCLOUD_SERVER_NAME}'"

# ── Inject machine config ─────────────────────────────────────────────────────
inject_machine_config \
  "${MACHINE_NAME}" "${SERVER_IP}" "${TEMP_PUBKEY}" \
  "${CONFIG_LOCAL}" "${CONFIG_LOCAL_BAK}"
register_cleanup "restore_machine_config '${CONFIG_LOCAL}' '${CONFIG_LOCAL_BAK}'"

# ── Wait for SSH ──────────────────────────────────────────────────────────────
wait_for_ssh "${SERVER_IP}" 22 180
sleep 5
SSH_OPTS_ARRAY=( $(build_ssh_opts "${SSH_KEY_FILE}") )
verify_ssh_auth "${SERVER_IP}" "${SSH_KEY_FILE}" root

# ── Run stackpanel provision (dry-run) ────────────────────────────────────────
run_stackpanel_provision "${MACHINE_NAME}" "${SERVER_IP}" dry-run --no-hardware-config
