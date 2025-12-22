#!/usr/bin/env bash
# Devshell loader for VS Code integrated terminal
# This script is sourced by VS Code to enter the devenv shell

# Find the project root (where this script lives relative to)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

cd "$PROJECT_ROOT"

# Check if devenv is available
if command -v devenv &> /dev/null; then
    # Enter devenv shell
    eval "$(devenv print-dev-env)"
elif [ -f .envrc ]; then
    # Fallback to direnv
    if command -v direnv &> /dev/null; then
        eval "$(direnv export bash)"
    fi
fi
