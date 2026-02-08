#!/usr/bin/env bash
# ==============================================================================
# run-tests.sh - Run all test fixtures
#
# Usage:
#   ./run-tests.sh                    # Run all fixtures
#   ./run-tests.sh basic with-oxlint  # Run specific fixtures
#   STACKPANEL_PATH=/path/to/stackpanel ./run-tests.sh  # Override stackpanel input
#
# This script can be used:
#   1. In stackpanel's own CI to test modules
#   2. By external modules to test against stackpanel templates
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKPANEL_PATH="${STACKPANEL_PATH:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Stackpanel Test Fixtures"
echo "=========================================="
echo "Stackpanel path: $STACKPANEL_PATH"
echo ""

# Get list of fixtures to run
if [ $# -gt 0 ]; then
	FIXTURES=("$@")
else
	FIXTURES=()
	for dir in "$SCRIPT_DIR"/*/; do
		if [ -f "$dir/flake.nix" ]; then
			FIXTURES+=("$(basename "$dir")")
		fi
	done
fi

echo "Fixtures to test: ${FIXTURES[*]}"
echo ""

PASSED=0
FAILED=0
FAILED_FIXTURES=()

for fixture in "${FIXTURES[@]}"; do
	fixture_dir="$SCRIPT_DIR/$fixture"

	if [ ! -d "$fixture_dir" ]; then
		echo -e "${YELLOW}⚠ Fixture '$fixture' not found, skipping${NC}"
		continue
	fi

	if [ ! -f "$fixture_dir/flake.nix" ]; then
		echo -e "${YELLOW}⚠ Fixture '$fixture' has no flake.nix, skipping${NC}"
		continue
	fi

	echo "----------------------------------------"
	echo "Testing: $fixture"
	echo "----------------------------------------"

	# Run nix flake check with stackpanel override
	if nix flake check "$fixture_dir" \
		--override-input stackpanel "path:$STACKPANEL_PATH" \
		--no-write-lock-file \
		2>&1; then
		echo -e "${GREEN}✓ $fixture passed${NC}"
		((PASSED++))
	else
		echo -e "${RED}✗ $fixture failed${NC}"
		FAILED_FIXTURES+=("$fixture")
		((FAILED++))
	fi

	echo ""
done

echo "=========================================="
echo "Results"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"

if [ $FAILED -gt 0 ]; then
	echo ""
	echo "Failed fixtures:"
	for f in "${FAILED_FIXTURES[@]}"; do
		echo "  - $f"
	done
	exit 1
fi

echo ""
echo -e "${GREEN}All fixtures passed!${NC}"
