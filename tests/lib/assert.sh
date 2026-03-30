#!/usr/bin/env bash
# ==============================================================================
# tests/lib/assert.sh — lightweight assertion helpers for scenario tests
#
# Requires: tests/lib/common.sh must be sourced first (provides ok, die).
#
# Functions:
#   fail                    <msg>
#   assert_exit_code        <expected> <actual> [msg]
#   assert_file_exists      <path> [msg]
#   assert_json_field       <file> <jq_expr> <expected> [msg]
#   assert_output_contains  <output> <pattern> [msg]
# ==============================================================================

# fail <msg>
# Prints a failure message (prefixed with "Assertion failed:") and exits 1.
fail() {
  die "Assertion failed: $*"
}

# assert_exit_code <expected> <actual> [msg]
# Fails if <actual> != <expected>.
assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-exit code check}"
  if [[ "${actual}" -ne "${expected}" ]]; then
    fail "${msg}: expected exit code ${expected}, got ${actual}"
  fi
  ok "${msg}: exit code ${expected}"
}

# assert_file_exists <path> [msg]
# Fails if <path> does not exist on disk.
assert_file_exists() {
  local path="$1"
  local msg="${2:-file existence}"
  if [[ ! -f "${path}" ]]; then
    fail "${msg}: file not found: ${path}"
  fi
  ok "${msg}: ${path} exists"
}

# assert_json_field <file> <jq_expr> <expected> [msg]
# Fails if the jq expression evaluated against <file> does not equal <expected>.
assert_json_field() {
  local file="$1"
  local jq_expr="$2"
  local expected="$3"
  local msg="${4:-json field check}"
  local actual
  actual="$(jq -r "${jq_expr}" "${file}" 2>/dev/null || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${msg}: expected '${expected}', got '${actual}' (jq: ${jq_expr})"
  fi
  ok "${msg}: ${jq_expr} == '${expected}'"
}

# assert_output_contains <output> <pattern> [msg]
# Fails if grep cannot find <pattern> in <output>.
assert_output_contains() {
  local output="$1"
  local pattern="$2"
  local msg="${3:-output contains check}"
  if ! printf '%s' "${output}" | grep -q "${pattern}"; then
    fail "${msg}: pattern '${pattern}' not found in output"
  fi
  ok "${msg}: found '${pattern}'"
}
