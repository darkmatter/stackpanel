#!/usr/bin/env bash
# ==============================================================================
# tests/lib/ssh.sh — SSH connectivity helpers
#
# Requires: tests/lib/common.sh must be sourced first (provides log, ok, die).
#
# Functions:
#   wait_for_ssh <host> [port] [timeout_secs]
#   build_ssh_opts <key_file>         → prints options one per line
#   verify_ssh_auth <host> <key_file> [user]
# ==============================================================================

# wait_for_ssh <host> <port> <timeout_secs>
# Polls with nc until TCP <port> on <host> accepts a connection, or until
# <timeout_secs> seconds elapse.  Dies on timeout.
wait_for_ssh() {
  local host="$1"
  local port="${2:-22}"
  local timeout_secs="${3:-180}"

  local deadline=$(( $(date +%s) + timeout_secs ))
  local ready=false

  log "Waiting for SSH on ${host}:${port} (up to ${timeout_secs}s)..."
  while [[ $(date +%s) -lt ${deadline} ]]; do
    if nc -z -w 3 "${host}" "${port}" 2>/dev/null; then
      ready=true
      break
    fi
    printf "."
    sleep 5
  done
  printf "\n"

  if [[ "${ready}" == "false" ]]; then
    die "SSH port ${port} on ${host} did not become reachable within ${timeout_secs} seconds."
  fi
  ok "SSH port ${port} is open on ${host}"
}

# build_ssh_opts <key_file>
# Prints BatchMode SSH options to stdout, one value per line, suitable for
# reading into a bash array with:
#   mapfile -t SSH_OPTS < <(build_ssh_opts "${KEY_FILE}")
#   ssh "${SSH_OPTS[@]}" user@host cmd
build_ssh_opts() {
  local key_file="$1"
  printf -- '-i\n'
  printf -- '%s\n' "${key_file}"
  printf -- '-o\nStrictHostKeyChecking=no\n'
  printf -- '-o\nConnectTimeout=15\n'
  printf -- '-o\nBatchMode=yes\n'
  printf -- '-o\nUserKnownHostsFile=/dev/null\n'
}

# verify_ssh_auth <host> <key_file> [user]
# Sleeps briefly (let sshd fully initialise) then attempts an SSH login.
# Dies if authentication fails.
verify_ssh_auth() {
  local host="$1"
  local key_file="$2"
  local user="${3:-root}"

  # Give sshd a few extra seconds after the port opens to finish initialisation
  sleep 5

  local -a ssh_opts
  mapfile -t ssh_opts < <(build_ssh_opts "${key_file}")

  if ssh "${ssh_opts[@]}" "${user}@${host}" "uname -r" >/dev/null 2>&1; then
    ok "SSH authentication to ${user}@${host} succeeded"
  else
    die "SSH authentication to ${user}@${host} failed (key: ${key_file})"
  fi
}
