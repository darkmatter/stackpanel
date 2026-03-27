#!/usr/bin/env bash
# ==============================================================================
# update-golden.sh - Update golden snapshot files for test fixtures
#
# Usage:
#   ./update-golden.sh                    # Update all fixtures
#   ./update-golden.sh basic with-oxlint  # Update specific fixtures
#   STACKPANEL_PATH=/path/to/stackpanel ./update-golden.sh  # Override stackpanel input
#
# This script builds the snapshot derivation for each fixture and copies
# the result into the fixture's golden/ directory. The golden files are
# checked into git and used by `nix flake check` to detect regressions.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKPANEL_PATH="${STACKPANEL_PATH:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Update Golden Snapshot Files"
echo "=========================================="
echo "Stackpanel path: $STACKPANEL_PATH"
echo ""

# Get list of fixtures to update
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

echo "Fixtures to update: ${FIXTURES[*]}"
echo ""

UPDATED=0
SKIPPED=0
FAILED=0
FAILED_FIXTURES=()

for fixture in "${FIXTURES[@]}"; do
	fixture_dir="$SCRIPT_DIR/$fixture"

	if [ ! -d "$fixture_dir" ]; then
		echo -e "${YELLOW}⚠ Fixture '$fixture' not found, skipping${NC}"
		((SKIPPED++))
		continue
	fi

	if [ ! -f "$fixture_dir/flake.nix" ]; then
		echo -e "${YELLOW}⚠ Fixture '$fixture' has no flake.nix, skipping${NC}"
		((SKIPPED++))
		continue
	fi

	echo "----------------------------------------"
	echo -e "${CYAN}Building snapshot: $fixture${NC}"
	echo "----------------------------------------"

	link="$fixture_dir/.snapshot-result"

	# Build the snapshot derivation
	if ! nix build "$fixture_dir#snapshot" \
		--override-input stackpanel "path:$STACKPANEL_PATH" \
		--no-write-lock-file \
		--out-link "$link" \
		2>&1; then
		echo -e "${RED}✗ Failed to build snapshot for $fixture${NC}"
		FAILED_FIXTURES+=("$fixture")
		((FAILED++))
		continue
	fi

	# Replace golden/ with snapshot contents
	rm -rf "$fixture_dir/golden"
	cp -rL "$link" "$fixture_dir/golden"
	chmod -R u+w "$fixture_dir/golden"
	rm -f "$link"

	# Show what was generated
	file_count=$(find "$fixture_dir/golden" -type f | wc -l | tr -d ' ')
	echo -e "${GREEN}✓ Updated golden/ for $fixture ($file_count files)${NC}"
	find "$fixture_dir/golden" -type f | sort | sed 's|.*/golden/|  |'
	echo ""
	((UPDATED++))
done

echo "=========================================="
echo "Results"
echo "=========================================="
echo -e "${GREEN}Updated: $UPDATED${NC}"
if [ $SKIPPED -gt 0 ]; then
	echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
fi
echo -e "${RED}Failed:  $FAILED${NC}"

if [ $FAILED -gt 0 ]; then
	echo ""
	echo "Failed fixtures:"
	for f in "${FAILED_FIXTURES[@]}"; do
		echo "  - $f"
	done
	exit 1
fi

echo ""
echo -e "${GREEN}Done! Remember to commit the updated golden/ directories.${NC}"
