#!/usr/bin/env bash
# ==============================================================================
# push-cachix.sh - push a build result to Cachix when credentials exist
#
# Local deploys do not always have Cachix push credentials configured. In that
# case we warn and continue so deployment can proceed without failing at the
# cache-push step. Other Cachix failures still fail fast.
# ==============================================================================
set -euo pipefail

CACHE_NAME="${1:?cache name required}"
RESULT_PATH="${2:?result path required}"

if ! command -v cachix >/dev/null 2>&1; then
  echo "==> Cachix not available; skipping binary cache push"
  exit 0
fi

TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_OUTPUT"' EXIT

set +e
cachix push "$CACHE_NAME" "$RESULT_PATH" >"$TMP_OUTPUT" 2>&1
STATUS=$?
set -e

OUTPUT="$(<"$TMP_OUTPUT")"

if [[ $STATUS -eq 0 ]]; then
  printf '%s\n' "$OUTPUT"
  exit 0
fi

if [[ "$OUTPUT" == *"Neither auth token nor signing key are present."* ]]; then
  echo "==> Skipping Cachix push for $CACHE_NAME"
  echo "    No Cachix auth token or signing key is configured in this shell."
  echo "    Set CACHIX_AUTH_TOKEN or CACHIX_SIGNING_KEY to enable local cache pushes."
  exit 0
fi

printf '%s\n' "$OUTPUT" >&2
exit $STATUS
