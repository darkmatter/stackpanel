#!/usr/bin/env bash
# ==============================================================================
# provision-hetzner-e2e.sh
#
# End-to-end regression test for `stackpanel provision` using ephemeral
# Hetzner Cloud instances.
#
# Usage:
#   ./tests/provision-hetzner-e2e.sh [OPTIONS]
#
# Options:
#   --setup-check   Validate prerequisites and SOPS access only; no cloud
#                   resources are created (fastest verification mode)
#   --dry-run       Create the Hetzner server, verify SSH reachability, then
#                   run `stackpanel provision --dry-run` to validate the config
#                   and command plan without invoking nixos-anywhere (default
#                   regression mode — safe to run in CI)
#   --full          Full end-to-end provision: creates server and runs the
#                   complete `stackpanel provision` workflow including
#                   nixos-anywhere.  Requires a NixOS configuration at
#                   .#ephemeral-provision-test in the flake, nixos-anywhere in
#                   PATH, and a Linux Nix builder for cross-compilation.
#   -h, --help      Show this help text and exit
#
# Prerequisites (all available in the devshell after `nix develop --impure`):
#   - hcloud      Hetzner Cloud CLI
#   - sops        For decrypting hetzner_api_key from shared.sops.yaml
#   - ssh, ssh-keygen, nc  Standard tools
#   - stackpanel  The stackpanel CLI binary
#   - jq          JSON parsing
#   - nixos-anywhere  Required for --full mode only
#
# What the script does:
#   1. Loads HCLOUD_TOKEN from SOPS key `hetzner_api_key` in
#      .stack/secrets/vars/shared.sops.yaml
#   2. Generates a temporary SSH key pair
#   3. Registers the key with Hetzner and creates an ephemeral CX22 server
#      in fsn1 running Debian 12
#   4. Injects an ephemeral machine config via .stack/config.local.nix
#      (backs up any existing content and restores on exit)
#   5. Waits for SSH to become available on the new server
#   6. Runs `stackpanel provision ephemeral-provision-test --install-target <IP>`
#      (with --dry-run unless --full is passed)
#   7. Cleans up: deletes the Hetzner server, SSH key, and removes the injected
#      machine config from .stack/config.local.nix, in a trap that fires even
#      on error or signal
#
# Exit codes:
#   0  All checks/provisions passed
#   1  One or more steps failed
# ==============================================================================
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MACHINE_NAME="ephemeral-provision-test"
SUFFIX="$(date +%s)-$$"
HCLOUD_SERVER_NAME="stackpanel-e2e-${SUFFIX}"
HCLOUD_KEY_NAME="stackpanel-e2e-${SUFFIX}"
SECRETS_FILE="${REPO_ROOT}/.stack/secrets/vars/shared.sops.yaml"
CONFIG_LOCAL="${REPO_ROOT}/.stack/config.local.nix"
CONFIG_LOCAL_BAK="${REPO_ROOT}/.stack/config.local.nix.provision-e2e-bak"
TMPDIR_SCRIPT="$(mktemp -d)"

# Mutable state set by the script; read by cleanup trap
SERVER_ID=""
KEY_ID=""
CONFIG_BACKED_UP=false
CONFIG_CREATED=false

# ── Mode flags ─────────────────────────────────────────────────────────────────

MODE="dry-run"  # default: create server + provision --dry-run
case "${1:-}" in
  --setup-check) MODE="setup-check" ;;
  --dry-run)     MODE="dry-run" ;;
  --full)        MODE="full" ;;
  -h|--help)
    sed -n '/^# ==/,/^set -euo/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
    exit 0
    ;;
  "")            : ;;  # no arg → default (dry-run)
  *)
    echo "Unknown option: ${1}" >&2
    echo "Run with --help for usage." >&2
    exit 1
    ;;
esac

# ── Colour helpers ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()  { printf "${BLUE}${BOLD}==>%s${NC} %s\n" "" "$*"; }
ok()   { printf "${GREEN}    ✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}    ⚠${NC} %s\n" "$*"; }
info() { printf "    %s\n" "$*"; }
die()  { printf "${RED}    ✗ FATAL:${NC} %s\n" "$*" >&2; exit 1; }

# ── Cleanup trap ───────────────────────────────────────────────────────────────

cleanup() {
  local exit_code=$?
  log "Cleaning up..."

  # Delete the Hetzner server (best-effort)
  if [[ -n "${SERVER_ID}" ]]; then
    if hcloud server delete "${SERVER_ID}" >/dev/null 2>&1; then
      ok "Deleted hcloud server ${SERVER_ID} (${HCLOUD_SERVER_NAME})"
    else
      warn "Failed to delete hcloud server ${SERVER_ID} — delete manually: hcloud server delete ${SERVER_ID}"
    fi
  fi

  # Delete the Hetzner SSH key (best-effort)
  if [[ -n "${KEY_ID}" ]]; then
    if hcloud ssh-key delete "${KEY_ID}" >/dev/null 2>&1; then
      ok "Deleted hcloud SSH key ${KEY_ID} (${HCLOUD_KEY_NAME})"
    else
      warn "Failed to delete hcloud SSH key ${KEY_ID} — delete manually: hcloud ssh-key delete ${KEY_ID}"
    fi
  fi

  # Restore .stack/config.local.nix
  if [[ "${CONFIG_BACKED_UP}" == "true" ]]; then
    if cp "${CONFIG_LOCAL_BAK}" "${CONFIG_LOCAL}" 2>/dev/null; then
      rm -f "${CONFIG_LOCAL_BAK}"
      ok "Restored .stack/config.local.nix from backup"
    else
      warn "Could not restore .stack/config.local.nix — backup is at ${CONFIG_LOCAL_BAK}"
    fi
  elif [[ "${CONFIG_CREATED}" == "true" ]]; then
    rm -f "${CONFIG_LOCAL}"
    rm -f "${CONFIG_LOCAL_BAK}"
    ok "Removed ephemeral .stack/config.local.nix"
  fi

  # Clean up temp directory
  rm -rf "${TMPDIR_SCRIPT}"

  if [[ ${exit_code} -eq 0 ]]; then
    printf "\n${GREEN}${BOLD}Test passed.${NC}\n"
  else
    printf "\n${RED}${BOLD}Test FAILED (exit code ${exit_code}).${NC}\n" >&2
  fi
}
trap cleanup EXIT

# ── Step 1: Validate prerequisites ────────────────────────────────────────────

log "Validating prerequisites..."

SOPS_BIN="$(command -v sops 2>/dev/null \
  || (command -v direnv &>/dev/null && direnv exec "${REPO_ROOT}" bash -lc 'command -v sops' 2>/dev/null) \
  || echo "")"
if [[ -z "${SOPS_BIN}" ]]; then
  die "sops not found. Run inside the devshell: nix develop --impure"
fi
ok "sops found: ${SOPS_BIN}"

for tool in hcloud jq ssh ssh-keygen nc; do
  if ! command -v "${tool}" &>/dev/null; then
    die "${tool} not found. Run inside the devshell: nix develop --impure"
  fi
  ok "${tool} found"
done

if ! command -v stackpanel &>/dev/null; then
  die "stackpanel CLI not found. Build it first: cd apps/stackpanel-go && go build -o \$(go env GOPATH)/bin/stackpanel ."
fi
ok "stackpanel found: $(command -v stackpanel)"

if [[ "${MODE}" == "full" ]] && ! command -v nixos-anywhere &>/dev/null; then
  die "nixos-anywhere not found (required for --full mode). Add it to the devshell or install separately."
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  die "SOPS secrets file not found: ${SECRETS_FILE}"
fi
ok "SOPS secrets file found"

# ── Step 2: Load HCLOUD_TOKEN from SOPS ───────────────────────────────────────

log "Loading HCLOUD_TOKEN from SOPS (shared.sops.yaml → hetzner_api_key)..."

HCLOUD_TOKEN="$("${SOPS_BIN}" -d --extract '["hetzner_api_key"]' "${SECRETS_FILE}" 2>/dev/null || true)"
if [[ -z "${HCLOUD_TOKEN}" ]]; then
  die "Could not decrypt hetzner_api_key from ${SECRETS_FILE}. Check AGE key availability."
fi
export HCLOUD_TOKEN
ok "HCLOUD_TOKEN loaded (${#HCLOUD_TOKEN} chars)"

# Validate token works
if ! hcloud server-type list >/dev/null 2>&1; then
  die "HCLOUD_TOKEN appears invalid — Hetzner API rejected it."
fi
ok "HCLOUD_TOKEN validated against Hetzner API"

# ── Setup-check mode exits here ────────────────────────────────────────────────

if [[ "${MODE}" == "setup-check" ]]; then
  printf "\n${GREEN}${BOLD}Setup check passed.${NC} All prerequisites are met.\n"
  printf "Run without --setup-check to create an ephemeral server and test the provision flow.\n"
  exit 0
fi

# ── Step 3: Generate a temporary SSH key pair ──────────────────────────────────

log "Generating temporary SSH key pair..."
SSH_KEY_FILE="${TMPDIR_SCRIPT}/id_ed25519"
ssh-keygen -t ed25519 -f "${SSH_KEY_FILE}" -N "" -C "stackpanel-provision-e2e-test-${SUFFIX}" -q
TEMP_PUBKEY="$(cat "${SSH_KEY_FILE}.pub")"
ok "Generated ${SSH_KEY_FILE}"

# ── Step 4: Register SSH key with Hetzner ─────────────────────────────────────

log "Registering SSH key '${HCLOUD_KEY_NAME}' with Hetzner Cloud..."
KEY_OUTPUT="$(hcloud ssh-key create \
  --name "${HCLOUD_KEY_NAME}" \
  --public-key-file "${SSH_KEY_FILE}.pub" \
  --output json)"
KEY_ID="$(echo "${KEY_OUTPUT}" | jq -r '.id')"
ok "Registered SSH key (id: ${KEY_ID})"

# ── Step 5: Create ephemeral CX22 server ──────────────────────────────────────

log "Creating ephemeral CX22 server '${HCLOUD_SERVER_NAME}' (fsn1, debian-12)..."
SERVER_OUTPUT="$(hcloud server create \
  --name "${HCLOUD_SERVER_NAME}" \
  --type cx22 \
  --image debian-12 \
  --location fsn1 \
  --ssh-key "${HCLOUD_KEY_NAME}" \
  --output json)"
SERVER_ID="$(echo "${SERVER_OUTPUT}" | jq -r '.server.id')"
SERVER_IP="$(echo "${SERVER_OUTPUT}" | jq -r '.server.public_net.ipv4.ip')"
ok "Server created (id: ${SERVER_ID}, ip: ${SERVER_IP})"

# ── Step 6: Inject ephemeral machine config via .stack/config.local.nix ────────

log "Injecting ephemeral machine config into .stack/config.local.nix..."

if [[ -f "${CONFIG_LOCAL}" ]]; then
  # Back up the existing config.local.nix as a sibling file so it can be
  # imported from the new version via a relative Nix import path.
  cp "${CONFIG_LOCAL}" "${CONFIG_LOCAL_BAK}"
  CONFIG_BACKED_UP=true
  info "Backed up existing config.local.nix to $(basename "${CONFIG_LOCAL_BAK}")"

  # Write a combined module: import the backup + add the test machine.
  # lib.mkMerge merges the attribute definitions from both modules so that
  # the existing settings (e.g. aws.roles-anywhere.*) are preserved.
  cat > "${CONFIG_LOCAL}" << NIXEOF
# Generated by tests/provision-hetzner-e2e.sh — DO NOT EDIT MANUALLY
# Original config.local.nix is backed up as $(basename "${CONFIG_LOCAL_BAK}")
# and will be restored automatically when the test script exits.
{ config, lib, ... } @ args:
lib.mkMerge [
  (import ./$(basename "${CONFIG_LOCAL_BAK}") args)
  {
    # Ephemeral machine injected for provision regression testing.
    # The actual target IP is supplied via --install-target at provision time.
    deployment.machines.${MACHINE_NAME} = {
      host = "${SERVER_IP}";
      user = "root";
      system = "x86_64-linux";
      authorizedKeys = [
        "${TEMP_PUBKEY}"
      ];
    };
  }
]
NIXEOF
else
  # No existing config.local.nix — create a fresh one.
  CONFIG_CREATED=true
  cat > "${CONFIG_LOCAL}" << NIXEOF
# Generated by tests/provision-hetzner-e2e.sh — DO NOT EDIT MANUALLY
# This file will be removed automatically when the test script exits.
{ ... }:
{
  # Ephemeral machine injected for provision regression testing.
  # The actual target IP is supplied via --install-target at provision time.
  deployment.machines.${MACHINE_NAME} = {
    host = "${SERVER_IP}";
    user = "root";
    system = "x86_64-linux";
    authorizedKeys = [
      "${TEMP_PUBKEY}"
    ];
  };
}
NIXEOF
fi
ok "config.local.nix updated with ephemeral machine '${MACHINE_NAME}'"

# ── Step 7: Wait for SSH ───────────────────────────────────────────────────────

log "Waiting for SSH to become available on ${SERVER_IP} (up to 3 minutes)..."
DEADLINE=$(( $(date +%s) + 180 ))
SSH_READY=false
while [[ $(date +%s) -lt ${DEADLINE} ]]; do
  if nc -z -w 3 "${SERVER_IP}" 22 2>/dev/null; then
    SSH_READY=true
    break
  fi
  printf "."
  sleep 5
done
printf "\n"

if [[ "${SSH_READY}" == "false" ]]; then
  die "SSH port 22 on ${SERVER_IP} did not open within 3 minutes."
fi
ok "SSH port 22 is open on ${SERVER_IP}"

# Give sshd another few seconds to fully initialise before attempting auth
sleep 5

# Verify actual SSH authentication with the temp key
SSH_OPTS=(
  -i "${SSH_KEY_FILE}"
  -o "StrictHostKeyChecking=no"
  -o "ConnectTimeout=15"
  -o "BatchMode=yes"
  -o "UserKnownHostsFile=/dev/null"
)
if ssh "${SSH_OPTS[@]}" "root@${SERVER_IP}" "uname -r" >/dev/null 2>&1; then
  ok "SSH authentication to root@${SERVER_IP} succeeded"
else
  die "SSH authentication to root@${SERVER_IP} failed (key: ${SSH_KEY_FILE})"
fi

# ── Step 8: Run stackpanel provision ──────────────────────────────────────────

log "Running stackpanel provision ${MACHINE_NAME} --install-target ${SERVER_IP}..."

PROVISION_EXTRA_FLAGS=()

if [[ "${MODE}" == "dry-run" ]]; then
  # Default regression mode: validate the provision workflow without invoking
  # nixos-anywhere.  This exercises config loading, machine lookup, and SSH
  # target resolution.  Remove --dry-run (--full mode) once the flake exposes
  # a nixosConfigurations.${MACHINE_NAME} output and a Linux Nix builder is
  # available.
  PROVISION_EXTRA_FLAGS+=("--dry-run")
  info "Mode: dry-run (config + command plan validated; nixos-anywhere NOT invoked)"
  info "Use --full to run the complete provision including nixos-anywhere."
fi

PROVISION_EXTRA_FLAGS+=("--no-hardware-config")
# NOTE: --no-hardware-config avoids the SSH hardware-detection step so the
# dry-run exercises the full command path without an extra SSH round-trip.

(
  cd "${REPO_ROOT}"
  stackpanel provision "${MACHINE_NAME}" \
    --install-target "${SERVER_IP}" \
    "${PROVISION_EXTRA_FLAGS[@]}"
)
ok "stackpanel provision completed${MODE:+ (${MODE} mode)}"
