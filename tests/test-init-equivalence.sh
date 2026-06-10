#!/usr/bin/env bash
# ==============================================================================
# test-init-equivalence.sh
#
# Drift guard: asserts that `stackpanel init` and `nix flake init -t` produce
# byte-for-byte identical scaffolding.
#
# `stackpanel init` writes the map evaluated from <flake>#lib.initFiles, which
# is derived from nix/flake/templates/default/. `nix flake init -t` copies that
# same directory. This test materializes both and diffs them, catching:
#   - lib.initFiles eval errors (e.g. stale paths after a template rename)
#   - any transformation/omission between the template dir and initFiles
#
# Usage:
#   ./tests/test-init-equivalence.sh
#
# Exit codes:
#   0 - Both paths produce identical files
#   1 - Drift detected (or eval failure)
# ==============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stackpanel-init-equivalence.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

FLAKE_REF="path:$PROJECT_ROOT"
TEMPLATE_NAME="default"

flake_init_dir="$TEMP_DIR/flake-init"
init_files_dir="$TEMP_DIR/init-files"
mkdir -p "$flake_init_dir" "$init_files_dir"

echo "==> nix flake init -t $FLAKE_REF#$TEMPLATE_NAME"
(cd "$flake_init_dir" && nix flake init -t "$FLAKE_REF#$TEMPLATE_NAME")

echo "==> nix eval $FLAKE_REF#lib.initFiles (what 'stackpanel init' writes)"
init_files_json="$TEMP_DIR/init-files.json"
nix eval "$FLAKE_REF#lib.initFiles" --json > "$init_files_json"

# Materialize the initFiles map exactly like `stackpanel init` does:
# each (relative path -> contents) entry written verbatim.
jq -r 'keys[]' "$init_files_json" | while IFS= read -r rel; do
  mkdir -p "$init_files_dir/$(dirname "$rel")"
  jq -j --arg k "$rel" '.[$k]' "$init_files_json" > "$init_files_dir/$rel"
done

echo "==> diff"
if diff -r "$flake_init_dir" "$init_files_dir"; then
  echo -e "${GREEN}✓ stackpanel init and nix flake init produce identical files${NC}"
else
  echo -e "${RED}✗ Drift detected between lib.initFiles and templates/$TEMPLATE_NAME/${NC}" >&2
  echo "  lib.initFiles must stay derived from nix/flake/templates/$TEMPLATE_NAME/ (see nix/flake/exports.nix)" >&2
  exit 1
fi
