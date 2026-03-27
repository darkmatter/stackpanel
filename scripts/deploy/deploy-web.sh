#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

REGION="$(deploy_region "${1:-}")"

ROOTDIR="$(deploy_rootdir)"
STAGE="$(deploy_stage)"
VERSION="$(artifact_version "$ROOTDIR")"
BUCKET="$(artifact_bucket "$REGION")"
KEY="$(artifact_key "$STAGE" "$VERSION")"
DEFAULT_SECRETS_FILE="${ROOTDIR}/.stack/secrets/vars/dev.sops.yaml"
STAGE_SECRETS_FILE="${ROOTDIR}/.stack/secrets/vars/${STAGE}.sops.yaml"
SECRETS_FILE="${STACKPANEL_DEPLOY_SECRETS_FILE:-}"
ALCHEMY_ENTRY="${ROOTDIR}/packages/infra/alchemy.run.ts"
LOCAL_AGE_KEY_FILE="${ROOTDIR}/.stack/keys/local.txt"

if [ -z "$SECRETS_FILE" ]; then
  if [ -f "$STAGE_SECRETS_FILE" ]; then
    SECRETS_FILE="$STAGE_SECRETS_FILE"
  else
    SECRETS_FILE="$DEFAULT_SECRETS_FILE"
  fi
fi

if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_CMD:-}" ] && [ -f "$LOCAL_AGE_KEY_FILE" ]; then
  export SOPS_AGE_KEY_FILE="$LOCAL_AGE_KEY_FILE"
fi

SOPS_BIN="$(command -v sops 2>/dev/null || direnv exec "$ROOTDIR" bash -lc 'command -v sops')"

echo "==> Deploying web"
echo "    Region:  ${REGION}"
echo "    Stage:   ${STAGE}"
echo "    Version: ${VERSION}"
echo "    Secrets: ${SECRETS_FILE}"

EC2_ARTIFACT_VERSION="$VERSION" \
EC2_ARTIFACT_BUCKET="$BUCKET" \
EC2_ARTIFACT_KEY="$KEY" \
bash "${SCRIPT_DIR}/build-artifact.sh" "$REGION"

EC2_ARTIFACT_VERSION="$VERSION" \
EC2_ARTIFACT_BUCKET="$BUCKET" \
EC2_ARTIFACT_KEY="$KEY" \
bash "${SCRIPT_DIR}/publish-artifact.sh" "$REGION"

echo "==> Running alchemy deploy"

if [ -z "${ALCHEMY_PASSWORD:-}" ]; then
  ALCHEMY_PASSWORD="$("$SOPS_BIN" -d --extract '["alchemy-password"]' "$SECRETS_FILE" 2>/dev/null || echo "stackpanel-deploy-$(id -un)")"
fi

"$SOPS_BIN" exec-env "$SECRETS_FILE" \
  "env \
    ALCHEMY_CI_STATE_STORE_CHECK=false \
    ALCHEMY_PASSWORD=$(printf '%q' "$ALCHEMY_PASSWORD") \
    AWS_REGION=$(printf '%q' "$REGION") \
    STACKPANEL_INFRA_INPUTS=$(printf '%q' "$ROOTDIR/.stack/profile/infra-inputs.json") \
    STACKPANEL_DEPLOYMENT_APP=web \
    STAGE=$(printf '%q' "$STAGE") \
    EC2_ARTIFACT_BUCKET=$(printf '%q' "$BUCKET") \
    EC2_ARTIFACT_KEY=$(printf '%q' "$KEY") \
    EC2_ARTIFACT_VERSION=$(printf '%q' "$VERSION") \
    bun $(printf '%q' "$ALCHEMY_ENTRY")"
