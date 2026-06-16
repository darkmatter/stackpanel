#!/usr/bin/env bash
# ==============================================================================
# smoke-test.sh
#
# Smoke tests for the Stackpanel development shell.
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
PROJECT_PATH="."

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --shell|--both|--native)
      shift
      ;;
    --help)
      echo "Usage: $0 [--project PATH]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

cd "$PROJECT_PATH"

log_info() {
  echo -e "${BLUE}i${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_error() {
  echo -e "${RED}x${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}!${NC} $*"
}

run_test() {
  local test_name="$1"
  local test_command="$2"

  TESTS_RUN=$((TESTS_RUN + 1))

  if eval "$test_command" >/dev/null 2>&1; then
    log_success "$test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    log_error "$test_name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

test_shell_builds() {
  log_info "Testing shell builds..."
  run_test "shell builds" "STACKPANEL_QUIET=1 nix develop --command true"
}

test_packages_available() {
  local packages=("$@")

  log_info "Testing packages in shell..."

  local failed=0
  for pkg in "${packages[@]}"; do
    if STACKPANEL_QUIET=1 nix develop --command which "$pkg" >/dev/null 2>&1; then
      log_success "  $pkg is available"
    else
      log_error "  $pkg is NOT available"
      failed=1
    fi
  done

  return $failed
}

test_env_vars() {
  local vars=("$@")

  log_info "Testing environment variables..."

  for var in "${vars[@]}"; do
    if STACKPANEL_QUIET=1 nix develop --command bash -c "test -n \"\${$var:-}\"" 2>/dev/null; then
      log_success "  $var is set"
    else
      log_warn "  $var is not set"
    fi
  done

  return 0
}

test_hooks_execute() {
  log_info "Testing hooks execute..."
  run_test "hooks execute" "STACKPANEL_QUIET=1 nix develop --command true"
}

main() {
  local exit_code=0

  echo ""
  echo "======================================================================"
  echo "Stackpanel Smoke Tests"
  echo "======================================================================"
  echo "Project: $PROJECT_PATH"
  echo ""

  test_shell_builds || exit_code=1

  local core_packages=(git jq)
  test_packages_available "${core_packages[@]}" || exit_code=1

  local env_vars=(STACKPANEL_ROOT STACKPANEL_STATE_DIR)
  test_env_vars "${env_vars[@]}"

  test_hooks_execute || exit_code=1

  echo ""
  echo "======================================================================"
  echo "Test Summary"
  echo "======================================================================"
  echo "Total tests: $TESTS_RUN"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  else
    echo "Failed: $TESTS_FAILED"
  fi
  echo ""

  if [[ $exit_code -eq 0 ]] && [[ $TESTS_FAILED -eq 0 ]]; then
    log_success "All tests passed!"
  else
    log_error "Some tests failed"
  fi

  return $exit_code
}

main
