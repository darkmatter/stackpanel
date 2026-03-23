#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

ROOTDIR="$(deploy_rootdir)"
STAGE="$(deploy_stage)"
VERSION="$(artifact_version "$ROOTDIR")"
ARTIFACT_PATH="$(artifact_local_path "$ROOTDIR" "$STAGE" "$VERSION")"

ensure_artifact_dir "$ROOTDIR" "$STAGE" "$VERSION"

echo "==> Building web artifact"
echo "    Stage:   ${STAGE}"
echo "    Version: ${VERSION}"

cd "$ROOTDIR"

ensure_preflight_manifest() {
  if [ -n "${STACKPANEL_FILES_PREFLIGHT_MANIFEST:-}" ]; then
    return
  fi

  local manifest_path
  manifest_path="$(nix eval --impure --raw ".#devShells.$(nix eval --impure --raw --expr builtins.currentSystem).default.STACKPANEL_FILES_PREFLIGHT_MANIFEST")"

  if [ -z "$manifest_path" ]; then
    echo "ERROR: could not resolve STACKPANEL_FILES_PREFLIGHT_MANIFEST via nix eval" >&2
    exit 1
  fi

  export STACKPANEL_FILES_PREFLIGHT_MANIFEST="$manifest_path"
}

echo "==> Running preflight"
ensure_preflight_manifest
if command -v go >/dev/null 2>&1; then
  (cd "$ROOTDIR/apps/stackpanel-go" && go run . preflight run --project-root "$ROOTDIR")
else
  nix develop --impure "path:$ROOTDIR" -c bash -lc "cd $(printf '%q' "$ROOTDIR/apps/stackpanel-go") && STACKPANEL_FILES_PREFLIGHT_MANIFEST=$(printf '%q' "$STACKPANEL_FILES_PREFLIGHT_MANIFEST") go run . preflight run --project-root $(printf '%q' "$ROOTDIR")"
fi

bun install --frozen-lockfile 2>/dev/null || bun install
BUILD_NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=8192"
if (
  cd "$ROOTDIR/apps/web" &&
  [ -f package.json ] &&
  python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("package.json").read_text())
print("build:ec2" in data.get("scripts", {}))
PY
) | grep -qx 'True'; then
  (cd apps/web && unset ALCHEMY && NODE_OPTIONS="$BUILD_NODE_OPTIONS" bun run build:ec2)
else
  (cd apps/web && unset ALCHEMY && NODE_OPTIONS="$BUILD_NODE_OPTIONS" bun x vite build)
fi

echo "==> Packaging artifact"
export COPYFILE_DISABLE=1
tar \
  -czf "$ARTIFACT_PATH" \
  -C "$ROOTDIR/apps/web" \
  .output

echo "Artifact: ${ARTIFACT_PATH}"
echo "Size: $(du -h "$ARTIFACT_PATH" | cut -f1)"
