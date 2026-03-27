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
ARTIFACT_PATH="$(artifact_local_path "$ROOTDIR" "$STAGE" "$VERSION")"
S3_URI="$(artifact_s3_uri "$BUCKET" "$KEY")"

if [ ! -f "$ARTIFACT_PATH" ]; then
  echo "artifact not found: ${ARTIFACT_PATH}" >&2
  echo "run build-artifact first or set EC2_ARTIFACT_VERSION to the desired version" >&2
  exit 1
fi

echo "==> Publishing artifact to S3"
echo "    File:   ${ARTIFACT_PATH}"
echo "    Bucket: ${BUCKET}"
echo "    Key:    ${KEY}"

ensure_artifact_bucket "$BUCKET" "$REGION"
aws s3 cp "$ARTIFACT_PATH" "$S3_URI" --region "$REGION"

echo "EC2_ARTIFACT_BUCKET=${BUCKET}"
echo "EC2_ARTIFACT_KEY=${KEY}"
echo "EC2_ARTIFACT_VERSION=${VERSION}"
