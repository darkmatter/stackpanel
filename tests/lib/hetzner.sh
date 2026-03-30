#!/usr/bin/env bash
# ==============================================================================
# tests/lib/hetzner.sh — Hetzner Cloud CLI helpers
#
# Requires: tests/lib/common.sh must be sourced first (provides log, ok, warn,
#           die).
# Assumes HCLOUD_TOKEN is exported in the environment before calling any
# function that makes API calls.
#
# Functions:
#   hetzner_require_token
#   hetzner_validate_token
#   hetzner_create_ssh_key  <name> <pubkey_file>    → JSON to stdout
#   hetzner_delete_ssh_key  <id>
#   hetzner_create_server   <name> <type> <image> <location> <key_name>  → JSON
#   hetzner_delete_server   <id> [name]
#   hetzner_server_ip       <server_json>            → IP to stdout
# ==============================================================================

# hetzner_require_token
# Verifies HCLOUD_TOKEN is non-empty in the environment.
hetzner_require_token() {
  if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    die "HCLOUD_TOKEN is not set. Load it via sops_load_key first."
  fi
}

# hetzner_validate_token
# Makes a lightweight Hetzner API call to confirm the token is accepted.
hetzner_validate_token() {
  hetzner_require_token
  if ! hcloud server-type list >/dev/null 2>&1; then
    die "HCLOUD_TOKEN appears invalid — Hetzner API rejected it."
  fi
  ok "HCLOUD_TOKEN validated against Hetzner API"
}

# hetzner_create_ssh_key <name> <pubkey_file>
# Registers a public key with Hetzner Cloud.
# Prints the full JSON response to stdout; caller should capture it and
# extract the id with: jq -r '.id'
hetzner_create_ssh_key() {
  local name="$1"
  local pubkey_file="$2"
  log "Registering SSH key '${name}' with Hetzner Cloud..."
  local output
  output="$(hcloud ssh-key create \
    --name "${name}" \
    --public-key-file "${pubkey_file}" \
    --output json)"
  ok "Registered SSH key (id: $(echo "${output}" | jq -r '.id'))"
  printf '%s' "${output}"
}

# hetzner_delete_ssh_key <id>
# Deletes a Hetzner Cloud SSH key by ID.
# Best-effort: logs a warning if deletion fails rather than dying.
hetzner_delete_ssh_key() {
  local key_id="$1"
  if hcloud ssh-key delete "${key_id}" >/dev/null 2>&1; then
    ok "Deleted hcloud SSH key ${key_id}"
  else
    warn "Failed to delete hcloud SSH key ${key_id} — delete manually: hcloud ssh-key delete ${key_id}"
  fi
}

# hetzner_create_server <name> <type> <image> <location> <key_name>
# Creates a Hetzner Cloud server.
# Prints the full JSON response to stdout; caller should extract .server.id
# and .server.public_net.ipv4.ip with jq, or use hetzner_server_ip().
hetzner_create_server() {
  local name="$1"
  local server_type="${2:-cx22}"
  local image="${3:-debian-12}"
  local location="${4:-fsn1}"
  local key_name="$5"
  log "Creating ${server_type} server '${name}' (${location}, ${image})..."
  local output
  output="$(hcloud server create \
    --name "${name}" \
    --type "${server_type}" \
    --image "${image}" \
    --location "${location}" \
    --ssh-key "${key_name}" \
    --output json)"
  ok "Server created (id: $(echo "${output}" | jq -r '.server.id'), ip: $(echo "${output}" | jq -r '.server.public_net.ipv4.ip'))"
  printf '%s' "${output}"
}

# hetzner_delete_server <id> [name]
# Deletes a Hetzner Cloud server by ID.
# Best-effort: logs a warning if deletion fails rather than dying.
hetzner_delete_server() {
  local server_id="$1"
  local server_name="${2:-}"
  local label="${server_id}${server_name:+ (${server_name})}"
  if hcloud server delete "${server_id}" >/dev/null 2>&1; then
    ok "Deleted hcloud server ${label}"
  else
    warn "Failed to delete hcloud server ${label} — delete manually: hcloud server delete ${server_id}"
  fi
}

# hetzner_server_ip <server_json_output>
# Extracts the IPv4 address from hcloud server create JSON output.
hetzner_server_ip() {
  printf '%s' "$1" | jq -r '.server.public_net.ipv4.ip'
}
