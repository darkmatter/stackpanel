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

# allow passing args to `nix build`
if [[ -n "$1" ]]; then
  shift
fi
NIX_ARGS=("$@")

echo "==> NixOS Deploy"
echo "    App:   $APP"
echo "    Stage: $STAGE"

# --------------------------------------------------------------------------
# 1. Build the Nix package (must target x86_64-linux for EC2)
# --------------------------------------------------------------------------
TARGET_SYSTEM="${DEPLOY_SYSTEM:-x86_64-linux}"
CURRENT_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"

if [[ "$CURRENT_SYSTEM" != "$TARGET_SYSTEM" ]]; then
  echo "==> Cross-building for $TARGET_SYSTEM (current system: $CURRENT_SYSTEM)"
  echo "    Requires a Linux builder (Determinate native builder or remote builder)"
fi

echo "==> Building nix package: .#packages.$TARGET_SYSTEM.$APP"
if ! nix build ".#packages.$TARGET_SYSTEM.$APP" --accept-flake-config "${NIX_ARGS[@]}"; then
  if [[ "$CURRENT_SYSTEM" != "$TARGET_SYSTEM" ]]; then
    echo ""
    echo "❌ Cross-build for $TARGET_SYSTEM failed (building on $CURRENT_SYSTEM)."
    echo ""
    echo "   A Linux builder is required. Options:"
    echo ""
    echo "   1. Determinate Nix Native Builder (recommended):"
    echo "        determinate-nixd auth login"
    echo "        sudo launchctl kickstart -k system/systems.determinate.nix-daemon"
    echo ""
    echo "   2. Remote builder (auto-configure):"
    echo "        Run: configure-linux-builder"
    echo ""
    echo "   3. Deploy from CI instead:"
    echo "        git push && trigger the deploy-nixos GitHub Actions workflow"
    echo ""
    echo "   To verify your builder works:"
    echo "        nix build --system $TARGET_SYSTEM nixpkgs#hello"
  fi
  exit 1
fi

echo "    Built: $(readlink -f result)"

# --------------------------------------------------------------------------
# 2. Push to Cachix
# --------------------------------------------------------------------------
CACHIX_CACHE="${CACHIX_CACHE_NAME:-darkmatter}"
echo "==> Pushing to Cachix ($CACHIX_CACHE)"
bash "$SCRIPT_DIR/push-cachix.sh" "$CACHIX_CACHE" ./result

# --------------------------------------------------------------------------
# 3. Run Alchemy infra (provisions EC2, SG, IAM, SSM — no instance replace)
# --------------------------------------------------------------------------
echo "==> Running Alchemy infra"
bash "$SCRIPT_DIR/run-alchemy-infra.sh" "$ROOT_DIR" "$APP"

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
