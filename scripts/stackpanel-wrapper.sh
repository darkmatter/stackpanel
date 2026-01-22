#!/usr/bin/env bash
# stackpanel-wrapper.sh
#
# Wrapper script for the stackpanel CLI that supports debug mode.
# When debug mode is enabled, it forwards commands to 'go run' in the local repo.
#
# Installation:
#   1. Install this script as 'stackpanel' in your PATH (before any other stackpanel)
#   2. Enable debug mode: stackpanel debug enable ~/path/to/stackpanel
#   3. All commands now run from source
#
# The actual installed binary should be named 'stackpanel-bin' or be at a known path.

set -euo pipefail

# Config file location (follows XDG spec)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stackpanel"
CONFIG_FILE="$CONFIG_DIR/stackpanel.yaml"

# Environment variable override (takes precedence over config file)
# Set STACKPANEL_DEV_REPO=/path/to/stackpanel to enable debug mode
DEV_REPO_ENV="${STACKPANEL_DEV_REPO:-}"

# Function to extract a value from YAML (simple parser for flat values)
yaml_get() {
    local key="$1"
    local file="$2"
    # Handle nested keys like dev_mode.enabled
    if [[ "$key" == *"."* ]]; then
        local parent="${key%%.*}"
        local child="${key#*.}"
        # Find the parent block and extract the child value
        awk -v parent="$parent" -v child="$child" '
            $0 ~ "^" parent ":" { in_block=1; next }
            in_block && /^[a-z_]+:/ { in_block=0 }
            in_block && $1 == child ":" { gsub(/^[^:]+: */, ""); gsub(/"/, ""); print; exit }
        ' "$file" 2>/dev/null
    else
        grep "^${key}:" "$file" 2>/dev/null | sed 's/^[^:]*: *//' | tr -d '"'
    fi
}

# Check if debug mode is enabled
check_dev_mode() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    local enabled
    enabled=$(yaml_get "dev_mode.enabled" "$CONFIG_FILE")

    if [[ "$enabled" == "true" ]]; then
        return 0
    fi
    return 1
}

# Get the dev repo path (env var takes precedence)
get_dev_repo_path() {
    # Check env var first
    if [[ -n "$DEV_REPO_ENV" ]]; then
        # Expand ~ if present
        local path="$DEV_REPO_ENV"
        if [[ "$path" == "~"* ]]; then
            path="$HOME${path:1}"
        fi
        echo "$path"
        return 0
    fi
    # Fall back to config file
    yaml_get "dev_mode.repo_path" "$CONFIG_FILE"
}

# Check if debug mode is enabled via env var
is_env_dev_mode() {
    [[ -n "$DEV_REPO_ENV" ]]
}

# Find the real stackpanel binary (not this wrapper)
find_real_binary() {
    # First, check for stackpanel-bin (the renamed original)
    if command -v stackpanel-bin &>/dev/null; then
        echo "stackpanel-bin"
        return 0
    fi

    # Check common installation paths
    local paths=(
        "/usr/local/bin/stackpanel-bin"
        "$HOME/.local/bin/stackpanel-bin"
        "$HOME/.nix-profile/bin/stackpanel"
        "/run/current-system/sw/bin/stackpanel"
    )

    for path in "${paths[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    # If this script is the wrapper, look for another stackpanel in PATH
    local self_path
    self_path=$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "")

    while IFS= read -r -d: path_dir; do
        local candidate="$path_dir/stackpanel"
        if [[ -x "$candidate" ]]; then
            local candidate_real
            candidate_real=$(realpath "$candidate" 2>/dev/null || echo "$candidate")
            # Skip if it's this script
            if [[ "$candidate_real" != "$self_path" ]]; then
                echo "$candidate"
                return 0
            fi
        fi
    done <<< "${PATH}:"

    return 1
}

# Main entry point
main() {
    # Special case: if running 'debug' (or legacy 'dev') subcommand, use debug mode if enabled
    if [[ "${1:-}" == "debug" || "${1:-}" == "dev" ]]; then
        # For debug commands, use go run if debug mode is enabled (env var or config)
        if is_env_dev_mode || check_dev_mode; then
            local repo_path
            repo_path=$(get_dev_repo_path)
            if [[ -n "$repo_path" && -d "$repo_path/apps/stackpanel-go" ]]; then
                if [[ "${STACKPANEL_DEBUG:-}" == "1" ]]; then
                    echo "[debug-mode] Running: cd $repo_path/apps/stackpanel-go && go run . $*" >&2
                fi
                cd "$repo_path/apps/stackpanel-go"
                exec go run . "$@"
            fi
        fi

        # Fall through to real binary
        local real_binary
        if real_binary=$(find_real_binary); then
            exec "$real_binary" "$@"
        else
            echo "Error: Could not find stackpanel binary" >&2
            echo "Hint: Set STACKPANEL_DEV_REPO to your stackpanel repo path" >&2
            exit 1
        fi
    fi

    # Check if debug mode is enabled (env var or config file)
    if is_env_dev_mode || check_dev_mode; then
        local repo_path
        repo_path=$(get_dev_repo_path)

        if [[ -z "$repo_path" ]]; then
            echo "Warning: Debug mode enabled but repo path not set. Using installed binary." >&2
        elif [[ ! -d "$repo_path/apps/stackpanel-go" ]]; then
            echo "Warning: Debug repo path invalid: $repo_path" >&2
            echo "  Expected: $repo_path/apps/stackpanel-go" >&2
            echo "  Falling back to installed binary." >&2
        else
            # Run from source
            if [[ "${STACKPANEL_DEBUG:-}" == "1" ]]; then
                echo "[debug-mode] Running: cd $repo_path/apps/stackpanel-go && go run . $*" >&2
            fi
            cd "$repo_path/apps/stackpanel-go"
            exec go run . "$@"
        fi
    fi

    # Fall back to the real binary
    local real_binary
    if real_binary=$(find_real_binary); then
        exec "$real_binary" "$@"
    else
        echo "Error: Could not find stackpanel binary" >&2
        echo "Make sure stackpanel is installed, or enable debug mode:" >&2
        echo "  stackpanel debug enable <repo-path>" >&2
        exit 1
    fi
}

main "$@"
