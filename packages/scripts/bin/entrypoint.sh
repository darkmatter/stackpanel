#!/usr/bin/env bash
# ==============================================================================
# entrypoint.sh - Generic CLI entrypoint runner for stackpanel apps
#
# This script provides a unified way to run any stackpanel app with proper
# environment setup (devshell, secrets).
#
# Usage:
#   ./entrypoint.sh <app> [--dev] [--env <environment>] [-- <app_args...>]
#
# Examples:
#   ./entrypoint.sh web --dev              # Run web app in dev mode
#   ./entrypoint.sh web                    # Run web app in prod mode
#   ./entrypoint.sh web --env staging      # Run with staging secrets
#   ./entrypoint.sh web --dev -- --port 3000  # Pass args to app
#
# Environment Variables:
#   STACKPANEL_ROOT       - Project root (auto-detected if not set)
#   STACKPANEL_DEBUG      - Set to 1 for debug logging
#   STACKPANEL_NO_SECRETS - Set to 1 to skip secrets loading
# ==============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source common library
if [[ -f "$LIB_DIR/common.sh" ]]; then
  # shellcheck source=../lib/common.sh
  source "$LIB_DIR/common.sh"
else
  echo "[ERROR] Could not find common.sh library at $LIB_DIR/common.sh" >&2
  exit 1
fi

# ==============================================================================
# Argument Parsing
# ==============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") <app> [options] [-- <app_args...>]

Run a stackpanel app with proper environment setup.

Arguments:
  <app>                   App name (e.g., web, server, docs)

Options:
  --dev                   Run in development mode (auto-sources devshell)
  --env <environment>     Environment for secrets (default: dev for --dev, prod otherwise)
  --no-secrets            Skip secrets loading
  --help                  Show this help message

Environment Variables:
  STACKPANEL_ROOT         Project root directory
  STACKPANEL_DEBUG        Enable debug logging (set to 1)
  STACKPANEL_NO_SECRETS   Skip secrets loading (set to 1)

Examples:
  $(basename "$0") web --dev              # Run web in dev mode
  $(basename "$0") web                    # Run web in prod mode
  $(basename "$0") web --env staging      # Run with staging secrets
  $(basename "$0") web --dev -- --port 3000  # Pass --port 3000 to app
EOF
}

# Default values
APP_NAME=""
DEV_MODE=false
ENVIRONMENT=""
SKIP_SECRETS=false
APP_ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      DEV_MODE=true
      shift
      ;;
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --no-secrets)
      SKIP_SECRETS=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      APP_ARGS=("$@")
      break
      ;;
    -*)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$APP_NAME" ]]; then
        APP_NAME="$1"
      else
        APP_ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

# Validate app name
if [[ -z "$APP_NAME" ]]; then
  log_error "App name is required"
  usage
  exit 1
fi

# Set default environment
if [[ -z "$ENVIRONMENT" ]]; then
  if [[ "$DEV_MODE" == "true" ]]; then
    ENVIRONMENT="dev"
  else
    ENVIRONMENT="prod"
  fi
fi

log_debug "App: $APP_NAME"
log_debug "Dev mode: $DEV_MODE"
log_debug "Environment: $ENVIRONMENT"
log_debug "Skip secrets: $SKIP_SECRETS"
log_debug "App args: ${APP_ARGS[*]:-}"

# ==============================================================================
# Find Project Root and Entrypoint
# ==============================================================================

PROJECT_ROOT=$(find_project_root) || die "Could not find project root"
log_debug "Project root: $PROJECT_ROOT"

# Look for app-specific entrypoint
ENTRYPOINTS_DIR="$SCRIPT_DIR/../entrypoints"
APP_ENTRYPOINT="$ENTRYPOINTS_DIR/$APP_NAME.sh"

if [[ -f "$APP_ENTRYPOINT" ]]; then
  log_debug "Found app entrypoint: $APP_ENTRYPOINT"
else
  # Fall back to generic execution
  log_debug "No app-specific entrypoint found, using generic execution"
  APP_ENTRYPOINT=""
fi

# ==============================================================================
# Environment Setup
# ==============================================================================

# Dev mode: ensure devshell
if [[ "$DEV_MODE" == "true" ]]; then
  ensure_devshell || die "Failed to set up devshell"
fi

# Load secrets (unless skipped)
if [[ "$SKIP_SECRETS" != "true" ]] && [[ "${STACKPANEL_NO_SECRETS:-}" != "1" ]]; then
  load_secrets "$APP_NAME" "$ENVIRONMENT" || log_warn "Secrets loading failed, continuing anyway"
fi

# ==============================================================================
# Execute App
# ==============================================================================

if [[ -n "$APP_ENTRYPOINT" ]]; then
  # Use app-specific entrypoint
  log_info "Running $APP_NAME via entrypoint"
  exec "$APP_ENTRYPOINT" "${APP_ARGS[@]}"
else
  # Generic execution: look for app in stackpanel config
  # Try to find app command from environment or config
  
  # Check if there's a command in an env var (set by Nix-generated entrypoint)
  APP_COMMAND="${STACKPANEL_APP_COMMAND:-}"
  
  if [[ -z "$APP_COMMAND" ]]; then
    # Try to get from stackpanel CLI if available
    if command_exists stackpanel; then
      APP_PATH=$(stackpanel config get "apps.$APP_NAME.path" 2>/dev/null) || APP_PATH="apps/$APP_NAME"
    else
      APP_PATH="apps/$APP_NAME"
    fi
    
    # Default commands based on mode
    if [[ "$DEV_MODE" == "true" ]]; then
      APP_COMMAND="bun run dev"
    else
      APP_COMMAND="bun run start"
    fi
  fi
  
  log_info "Running $APP_NAME: $APP_COMMAND"
  
  # Change to app directory
  APP_DIR="$PROJECT_ROOT/${APP_PATH:-apps/$APP_NAME}"
  if [[ -d "$APP_DIR" ]]; then
    cd "$APP_DIR"
    log_debug "Changed to app directory: $APP_DIR"
  else
    log_warn "App directory not found: $APP_DIR, running from project root"
    cd "$PROJECT_ROOT"
  fi
  
  # Execute the command
  # shellcheck disable=SC2086
  exec $APP_COMMAND "${APP_ARGS[@]}"
fi
