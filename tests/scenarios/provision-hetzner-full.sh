#!/usr/bin/env bash
# ==============================================================================
# scenarios/provision-hetzner-full.sh
#
# Full end-to-end provision: creates ephemeral Hetzner CX22, injects machine
# config, and runs the complete `stackpanel provision` workflow including
# nixos-anywhere.
#
# Prerequisites beyond dry-run:
#   - nixos-anywhere in PATH (add to devshell — future task)
#   - A NixOS config exposed at .#nixosConfigurations.ephemeral-provision-test
#     in the flake (future task)
#   - Linux Nix builder accessible for cross-compilation on macOS
#
# Usage:   bash tests/scenarios/provision-hetzner-full.sh
# Or via:  just test-scenario provision-hetzner-full
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

log "[scenario] provision-hetzner-full"

# ── Validate tools ────────────────────────────────────────────────────────────
log "Validating required tools..."
require_command hcloud
require_command jq
require_command ssh
require_command ssh-keygen
require_command nc
require_command stackpanel "Build it first: cd apps/stackpanel-go && go build -o \$(go env GOPATH)/bin/stackpanel ."
require_command nixos-anywhere \
  "Add nixos-anywhere to devshell packages and run: nix develop --impure"

# ── Validate flake config ─────────────────────────────────────────────────────
log "Checking flake exposes nixosConfigurations.${MACHINE_NAME}..."
if ! (cd "${REPO_ROOT}" && nix eval --impure ".#nixosConfigurations.${MACHINE_NAME}" \
    --apply "x: x != null" 2>/dev/null | grep -q true); then
  die "Flake does not expose nixosConfigurations.${MACHINE_NAME}.
Add it to your config.nix deployment.machines and run: nix flake check --impure
(This is required for the full provision path and is a separate future task.)"
fi
ok "nixosConfigurations.${MACHINE_NAME} found in flake"

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
verify_ssh_auth "${SERVER_IP}" "${SSH_KEY_FILE}" root

# ── Run full provision ────────────────────────────────────────────────────────
run_stackpanel_provision "${MACHINE_NAME}" "${SERVER_IP}" full

# ── Verify NixOS boot ─────────────────────────────────────────────────────────
log "Verifying NixOS boot on ${SERVER_IP}..."
SSH_OPTS_ARRAY=( -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes -o UserKnownHostsFile=/dev/null )
NIXOS_VERSION="$(ssh "${SSH_OPTS_ARRAY[@]}" "root@${SERVER_IP}" "nixos-version" 2>/dev/null || true)"
assert_output_contains "${NIXOS_VERSION}" "nixos" "nixos-version should contain 'nixos'"
ok "NixOS boot verified: ${NIXOS_VERSION}"

assert_file_exists \
  "${REPO_ROOT}/.stack/state/machines.json" \
  "machines.json should be created by provision"

log "Full provision scenario passed."
