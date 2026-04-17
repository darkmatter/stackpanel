#!/usr/bin/env bash
set -euo pipefail

# --- Parameters ---
APP="${1:?app required}"
STAGE="${2:-staging}"
REGION="${3:-us-west-2}"

# --- Constants ---
GITROOT="$(git rev-parse --show-toplevel)"
SECRETS_ROOT="${GITROOT}/.stack/secrets"
ALCHEMY_ENTRY="${GITROOT}/apps/${APP}/alchemy.run.ts"
APP_DIR="$(dirname "$ALCHEMY_ENTRY")"
LOCAL_AGE_KEY_FILE="${SECRETS_ROOT}/keys/local.txt"
SECRETS_FILE="${GITROOT}/packages/config/secrets/infra.sops.yaml"

# --- Environment Variables ---
# Env-specific
if [ -f "${SECRETS_ROOT}/vars/${STAGE}.sops.yaml" ]; then
  SECRETS_FILE="${SECRETS_ROOT}/vars/${STAGE}.sops.yaml"
fi

# Fallback to local age key file
if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_CMD:-}" ] && [ -f "$LOCAL_AGE_KEY_FILE" ]; then
  export SOPS_AGE_KEY_FILE="$LOCAL_AGE_KEY_FILE"
fi

SOPS_BIN="$(command -v sops 2>/dev/null || direnv exec "$GITROOT" bash -lc 'command -v sops')"

if [ -z "${ALCHEMY_PASSWORD:-}" ]; then
  echo "ALCHEMY_PASSWORD not set, using sops to decrypt secrets file"
  ALCHEMY_PASSWORD="$("$SOPS_BIN" -d  "$SECRETS_FILE" 2>/dev/null || echo "stackpanel-deploy-$(id -un)")"
fi
if [ -z "$ALCHEMY_PASSWORD" ]; then
  echo "ALCHEMY_PASSWORD not found after decryption, using default"
  ALCHEMY_PASSWORD="stackpanel-deploy-$(id -un)"
fi

echo "==> Running Alchemy deploy"
echo "    Region:  ${REGION}"
echo "    Stage:   ${STAGE}"
echo "    Secrets: ${SECRETS_FILE}"

cd "$APP_DIR"
"$SOPS_BIN" exec-env "$SECRETS_FILE" \
  "env \
    ALCHEMY_CI_STATE_STORE_CHECK=false \
    ALCHEMY_PASSWORD=$(printf '%q' "$ALCHEMY_PASSWORD") \
    AWS_REGION=$(printf '%q' "$REGION") \
    STACKPANEL_INFRA_INPUTS=$(printf '%q' "$GITROOT/.stack/profile/infra-inputs.json") \
    STACKPANEL_DEPLOYMENT_APP=$(printf '%q' "$APP") \
    STAGE=$(printf '%q' "$STAGE") \
    EC2_ARTIFACT_BUCKET=$(printf '%q' "${EC2_ARTIFACT_BUCKET:-}") \
    EC2_ARTIFACT_KEY=$(printf '%q' "${EC2_ARTIFACT_KEY:-}") \
    EC2_ARTIFACT_VERSION=$(printf '%q' "${EC2_ARTIFACT_VERSION:-}") \
    alchemy dev"