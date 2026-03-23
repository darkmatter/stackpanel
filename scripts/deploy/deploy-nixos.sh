#!/usr/bin/env bash
# ==============================================================================
# deploy-nixos.sh - NixOS-based deployment
#
# Flow: nix build -> cachix push -> alchemy infra -> colmena apply
#
# Unlike the AL2023 deploy, NixOS instances are long-lived. Deploys update
# the system configuration via Colmena (nixos-rebuild switch) and the
# pre-built closure is pulled from Cachix by the instance.
# ==============================================================================
set -euo pipefail

APP="${1:-web}"
STAGE="${STAGE:-staging}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> NixOS Deploy"
echo "    App:   $APP"
echo "    Stage: $STAGE"

# --------------------------------------------------------------------------
# 1. Build the Nix package
# --------------------------------------------------------------------------
echo "==> Building nix package: .#$APP"
nix build ".#$APP" --accept-flake-config

echo "    Built: $(readlink -f result)"

# --------------------------------------------------------------------------
# 2. Push to Cachix
# --------------------------------------------------------------------------
CACHIX_CACHE="${CACHIX_CACHE_NAME:-darkmatter}"
echo "==> Pushing to Cachix ($CACHIX_CACHE)"
cachix push "$CACHIX_CACHE" ./result

# --------------------------------------------------------------------------
# 3. Run Alchemy infra (provisions EC2, SG, IAM, SSM — no instance replace)
# --------------------------------------------------------------------------
echo "==> Running Alchemy infra"

SOPS_FILE="${STACKPANEL_DEPLOY_SECRETS_FILE:-}"
if [[ -z "$SOPS_FILE" ]]; then
  SOPS_FILE="$ROOT_DIR/.stack/secrets/vars/${STAGE}.sops.yaml"
  if [[ ! -f "$SOPS_FILE" ]]; then
    SOPS_FILE="$ROOT_DIR/.stack/secrets/vars/dev.sops.yaml"
  fi
fi

if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
  export SOPS_AGE_KEY_FILE="$ROOT_DIR/.stack/keys/local.txt"
fi

export STAGE
export STACKPANEL_DEPLOYMENT_APP="$APP"
export STACKPANEL_INFRA_INPUTS="${STACKPANEL_INFRA_INPUTS:-$ROOT_DIR/.stack/profile/infra-inputs.json}"
export ALCHEMY_CI_STATE_STORE_CHECK=false

if command -v sops &>/dev/null && [[ -f "$SOPS_FILE" ]]; then
  ALCHEMY_PASSWORD="${ALCHEMY_PASSWORD:-$(sops -d --extract '["alchemy-password"]' "$SOPS_FILE" 2>/dev/null || echo "stackpanel-dev-password")}"
  export ALCHEMY_PASSWORD

  sops exec-env "$SOPS_FILE" "bun $ROOT_DIR/packages/infra/alchemy.run.ts"
else
  export ALCHEMY_PASSWORD="${ALCHEMY_PASSWORD:-stackpanel-dev-password}"
  bun "$ROOT_DIR/packages/infra/alchemy.run.ts"
fi

# --------------------------------------------------------------------------
# 4. Deploy via Colmena
# --------------------------------------------------------------------------
echo "==> Deploying via Colmena"
if command -v colmena-apply &>/dev/null; then
  colmena-apply
else
  colmena apply --substitute-on-destination
fi

echo "==> NixOS deploy complete"
