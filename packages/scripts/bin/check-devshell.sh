#!/usr/bin/env bash
# Check if we're in the stackpanel devshell and auto-source if not

set -euo pipefail

# Allow skipping auto-source via env var
if [ "${STACKPANEL_NO_AUTO_SOURCE:-}" = "1" ]; then
  if [ -z "${IN_NIX_SHELL:-}" ]; then
    echo "❌ Error: Not in dev shell and STACKPANEL_NO_AUTO_SOURCE=1"
    echo ""
    echo "Please enter the dev shell first:"
    echo "  direnv allow"
    echo "  # or"
    echo "  nix develop --impure"
    echo ""
    exit 1
  fi
  exit 0
fi

# If already in Nix shell, we're good
if [ -n "${IN_NIX_SHELL:-}" ]; then
  exit 0
fi

# Try to auto-source the dev environment
echo "🔧 Not in dev shell, sourcing Nix environment..."

# Find the flake root (directory containing flake.nix)
FLAKE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -f "$FLAKE_ROOT/flake.nix" ]; then
  echo "❌ Error: Could not find flake.nix"
  echo ""
  echo "Please run from within the project or enter the dev shell:"
  echo "  direnv allow"
  echo "  # or"
  echo "  nix develop --impure"
  echo ""
  exit 1
fi

cd "$FLAKE_ROOT"

# Source the dev environment
if command -v nix >/dev/null 2>&1; then
  # Use nix print-dev-env to get the environment without entering a subshell
  eval "$(nix print-dev-env --impure 2>/dev/null)"
  echo "✅ Dev environment sourced"
  exit 0
else
  echo "❌ Error: nix command not found"
  echo ""
  echo "Please install Nix or enter the dev shell manually:"
  echo "  direnv allow"
  echo ""
  exit 1
fi
