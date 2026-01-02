#!/usr/bin/env bash
# ==============================================================================
# smoke-test.sh
#
# Smoke tests for stackpanel development environments.
# Tests both devenv and native nix shells to catch regressions.
#
# Usage:
#   ./tests/smoke-test.sh [--project PATH] [--devenv|--native|--both]
#
# Tests:
#   1. Shell builds successfully
#   2. Expected packages are available
#   3. Environment variables are set
#   4. Hooks execute without errors
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
# ==============================================================================
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Configuration
PROJECT_PATH="${1:-.}"
TEST_MODE="${2:-both}" # devenv, native, or both

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --devenv)
      TEST_MODE="devenv"
      shift
      ;;
    --native)
      TEST_MODE="native"
      shift
      ;;
    --both)
      TEST_MODE="both"
      shift
      ;;
    --help)
      echo "Usage: $0 [--project PATH] [--devenv|--native|--both]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

cd "$PROJECT_PATH"

# Logging functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

# Test execution
run_test() {
  local test_name="$1"
  local test_command="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if eval "$test_command" > /dev/null 2>&1; then
    log_success "$test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    log_error "$test_name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# Test shell can build
test_shell_builds() {
  local shell_type="$1"
  local flake_ref="$2"
  
  log_info "Testing $shell_type shell builds..."
  
  if nix build "$flake_ref" --no-link --impure 2>&1 | grep -q "error:"; then
    log_error "$shell_type shell failed to build"
    return 1
  else
    log_success "$shell_type shell builds successfully"
    return 0
  fi
}

# Test packages are available
test_packages_available() {
  local shell_type="$1"
  local flake_ref="$2"
  shift 2
  local packages=("$@")
  
  log_info "Testing packages in $shell_type shell..."
  
  local failed=0
  for pkg in "${packages[@]}"; do
    if nix shell "$flake_ref" --impure --command which "$pkg" > /dev/null 2>&1; then
      log_success "  $pkg is available"
    else
      log_error "  $pkg is NOT available"
      failed=1
    fi
  done
  
  return $failed
}

# Test environment variables
test_env_vars() {
  local shell_type="$1"
  local flake_ref="$2"
  shift 2
  local vars=("$@")
  
  log_info "Testing environment variables in $shell_type shell..."
  
  local failed=0
  for var in "${vars[@]}"; do
    if nix shell "$flake_ref" --impure --command bash -c "test -n \"\${$var:-}\"" 2>/dev/null; then
      log_success "  $var is set"
    else
      log_warn "  $var is not set (may be optional)"
    fi
  done
  
  return 0 # Env vars are warnings only
}

# Test shell hooks execute
test_hooks_execute() {
  local shell_type="$1"
  local flake_ref="$2"
  
  log_info "Testing hooks execute in $shell_type shell..."
  
  # Run a simple command to trigger hooks
  if nix shell "$flake_ref" --impure --command echo "test" > /dev/null 2>&1; then
    log_success "Hooks executed without errors"
    return 0
  else
    log_error "Hooks failed to execute"
    return 1
  fi
}

# Main test suite
run_test_suite() {
  local shell_type="$1"
  local flake_ref="$2"
  
  echo ""
  echo "======================================================================"
  echo "Testing $shell_type Shell"
  echo "======================================================================"
  echo ""
  
  # Test 1: Shell builds
  test_shell_builds "$shell_type" "$flake_ref" || return 1
  
  # Test 2: Core packages available
  # Adjust these based on your actual stackpanel config
  local core_packages=(
    "git"
    "jq"
  )
  test_packages_available "$shell_type" "$flake_ref" "${core_packages[@]}" || true
  
  # Test 3: Environment variables set
  local env_vars=(
    "STACKPANEL_ROOT"
    "STACKPANEL_STATE_DIR"
  )
  test_env_vars "$shell_type" "$flake_ref" "${env_vars[@]}"
  
  # Test 4: Hooks execute
  test_hooks_execute "$shell_type" "$flake_ref" || return 1
  
  echo ""
  return 0
}

# Run tests based on mode
main() {
  echo ""
  echo "======================================================================"
  echo "Stackpanel Smoke Tests"
  echo "======================================================================"
  echo "Project: $PROJECT_PATH"
  echo "Mode: $TEST_MODE"
  echo ""
  
  local exit_code=0
  
  if [[ "$TEST_MODE" == "devenv" ]] || [[ "$TEST_MODE" == "both" ]]; then
    if ! run_test_suite "devenv" ".#devShells.$(nix eval --impure --raw --expr 'builtins.currentSystem').default"; then
      exit_code=1
    fi
  fi
  
  if [[ "$TEST_MODE" == "native" ]] || [[ "$TEST_MODE" == "both" ]]; then
    # For native shell, we need to check if SKIP_DEVENV mode is available
    if SKIP_DEVENV=true nix build ".#devShells.$(nix eval --impure --raw --expr 'builtins.currentSystem').default" --no-link --impure 2>/dev/null; then
      if ! run_test_suite "native" ".#devShells.$(nix eval --impure --raw --expr 'builtins.currentSystem').default"; then
        exit_code=1
      fi
    else
      log_warn "Native shell mode not available (SKIP_DEVENV not supported)"
    fi
  fi
  
  # Summary
  echo ""
  echo "======================================================================"
  echo "Test Summary"
  echo "======================================================================"
  echo "Total tests: $TESTS_RUN"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  else
    echo -e "Failed: $TESTS_FAILED"
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
