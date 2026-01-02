#!/usr/bin/env bash
# ==============================================================================
# test-templates.sh
#
# Test all stackpanel templates to ensure they work correctly.
# Creates temporary projects from templates and runs smoke tests on them.
#
# Usage:
#   ./tests/test-templates.sh [--template NAME] [--keep-temp]
#
# Options:
#   --template NAME  Test only the specified template
#   --keep-temp      Don't delete temporary test directories
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
# ==============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="${TMPDIR:-/tmp}/stackpanel-template-tests"
KEEP_TEMP=false
SPECIFIC_TEMPLATE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --template)
      SPECIFIC_TEMPLATE="$2"
      shift 2
      ;;
    --keep-temp)
      KEEP_TEMP=true
      shift
      ;;
    --help)
      echo "Usage: $0 [--template NAME] [--keep-temp]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Logging
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

# Cleanup
cleanup() {
  if [[ "$KEEP_TEMP" == "false" ]]; then
    log_info "Cleaning up temporary directories..."
    rm -rf "$TEMP_DIR"
  else
    log_info "Keeping temporary directories in: $TEMP_DIR"
  fi
}

trap cleanup EXIT

# Test a single template
test_template() {
  local template_name="$1"
  local test_dir="$TEMP_DIR/$template_name"
  
  echo ""
  echo "======================================================================"
  echo "Testing template: $template_name"
  echo "======================================================================"
  echo ""
  
  # Create test directory
  log_info "Creating test project from template..."
  mkdir -p "$test_dir"
  
  # Initialize from template
  if ! nix flake init -t "$PROJECT_ROOT#$template_name" "$test_dir" 2>&1; then
    log_error "Failed to initialize template"
    return 1
  fi
  
  log_success "Template initialized"
  
  # Run smoke tests on the template
  log_info "Running smoke tests..."
  if "$SCRIPT_DIR/smoke-test.sh" --project "$test_dir" --both; then
    log_success "Template $template_name passed all tests"
    return 0
  else
    log_error "Template $template_name failed tests"
    return 1
  fi
}

# Main
main() {
  echo ""
  echo "======================================================================"
  echo "Stackpanel Template Tests"
  echo "======================================================================"
  echo ""
  
  # Get list of templates
  local templates
  if [[ -n "$SPECIFIC_TEMPLATE" ]]; then
    templates=("$SPECIFIC_TEMPLATE")
  else
    # List all templates from flake
    templates=($(nix flake show "$PROJECT_ROOT" 2>/dev/null | grep "template '" | sed "s/.*template '\(.*\)'.*/\1/" | sort -u))
  fi
  
  if [[ ${#templates[@]} -eq 0 ]]; then
    log_warn "No templates found to test"
    return 0
  fi
  
  log_info "Found ${#templates[@]} template(s) to test"
  echo ""
  
  # Test each template
  local failed=0
  for template in "${templates[@]}"; do
    if ! test_template "$template"; then
      failed=$((failed + 1))
    fi
  done
  
  # Summary
  echo ""
  echo "======================================================================"
  echo "Template Test Summary"
  echo "======================================================================"
  echo "Total templates tested: ${#templates[@]}"
  if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}All templates passed${NC}"
    return 0
  else
    echo -e "${RED}Failed templates: $failed${NC}"
    return 1
  fi
}

main
