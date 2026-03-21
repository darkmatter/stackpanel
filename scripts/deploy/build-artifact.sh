#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

REGION="$(deploy_region "${1:-}")"

ROOTDIR="$(deploy_rootdir)"
STAGE="$(deploy_stage)"
VERSION="$(artifact_version "$ROOTDIR")"
ARTIFACT_PATH="$(artifact_local_path "$ROOTDIR" "$STAGE" "$VERSION")"

ensure_artifact_dir "$ROOTDIR" "$STAGE" "$VERSION"

echo "==> Building web artifact"
echo "    Stage:   ${STAGE}"
echo "    Version: ${VERSION}"

cd "$ROOTDIR"

bun install --frozen-lockfile 2>/dev/null || bun install
(cd apps/web && bun run build:ec2)

echo "==> Packaging artifact"
export COPYFILE_DISABLE=1
tar \
  -czf "$ARTIFACT_PATH" \
  -C "$ROOTDIR/apps/web" \
  .output

echo "Artifact: ${ARTIFACT_PATH}"
echo "Size: $(du -h "$ARTIFACT_PATH" | cut -f1)"
