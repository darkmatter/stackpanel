#!/usr/bin/env bash
# ==============================================================================
# tests/lib/sops.sh — SOPS decryption helpers
#
# Requires: tests/lib/common.sh must be sourced first (provides die, ok, info,
#           REPO_ROOT).
#
# Functions exported:
#   find_sops_bin               → prints sops path to stdout; returns 1 if missing
#   validate_sops_file <file>   → dies if file does not exist
#   sops_load_key <file> <key> <envvar>  → decrypts key and exports as envvar
# ==============================================================================

# find_sops_bin
# Locates the sops binary; tries PATH first, then direnv exec fallback.
# Prints the path to stdout; returns 1 if not found anywhere.
find_sops_bin() {
  local bin
  bin="$(command -v sops 2>/dev/null)" && { echo "${bin}"; return 0; }
  if command -v direnv &>/dev/null; then
    bin="$(direnv exec "${REPO_ROOT}" bash -lc 'command -v sops' 2>/dev/null || true)"
    if [[ -n "${bin}" ]]; then
      echo "${bin}"; return 0
    fi
  fi
  return 1
}

# validate_sops_file <secrets_file>
# Checks that the SOPS-encrypted file exists on disk.
# Dies with a clear message if it is missing.
validate_sops_file() {
  local secrets_file="$1"
  if [[ ! -f "${secrets_file}" ]]; then
    die "SOPS secrets file not found: ${secrets_file}"
  fi
  ok "SOPS secrets file found: ${secrets_file}"
}

# sops_load_key <secrets_file> <key_name> <env_var_name>
# Decrypts <key_name> from <secrets_file> using sops and exports the value as
# the environment variable named <env_var_name>.
# Dies if decryption fails or the resulting value is empty.
sops_load_key() {
  local secrets_file="$1"
  local key_name="$2"
  local env_var_name="$3"

  local sops_bin
  sops_bin="$(find_sops_bin)" || die "sops not found. Run inside the devshell: nix develop --impure"

  local value
  value="$("${sops_bin}" -d --extract "[\"${key_name}\"]" "${secrets_file}" 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    die "Could not decrypt '${key_name}' from ${secrets_file}. Check AGE key availability."
  fi

  # Use printf + eval to handle env var names containing only safe characters
  eval "export ${env_var_name}=\${value}"
  ok "${env_var_name} loaded (${#value} chars)"
}
