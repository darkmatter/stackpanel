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
SECRETS_FILE="${ROOTDIR}/.stack/secrets/vars/dev.sops.yaml"
ALCHEMY_ENTRY="${ROOTDIR}/packages/infra/deploy-web.run.ts"

echo "==> Deploying web"
echo "    Region:  ${REGION}"
echo "    Stage:   ${STAGE}"
echo "    Version: ${VERSION}"

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
  ALCHEMY_PASSWORD="$(sops -d --extract '["alchemy-password"]' "$SECRETS_FILE" 2>/dev/null || echo "stackpanel-deploy-$(id -un)")"
fi

sops exec-env "$SECRETS_FILE" \
  "env \
    ALCHEMY_CI_STATE_STORE_CHECK=false \
    ALCHEMY_PASSWORD=$(printf '%q' "$ALCHEMY_PASSWORD") \
    AWS_REGION=$(printf '%q' "$REGION") \
    STAGE=$(printf '%q' "$STAGE") \
    EC2_ARTIFACT_BUCKET=$(printf '%q' "$BUCKET") \
    EC2_ARTIFACT_KEY=$(printf '%q' "$KEY") \
    EC2_ARTIFACT_VERSION=$(printf '%q' "$VERSION") \
    bun $(printf '%q' "$ALCHEMY_ENTRY")"
