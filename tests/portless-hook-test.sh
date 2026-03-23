#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORTLESS_MODULE="$PROJECT_ROOT/nix/stackpanel/services/portless.nix"

if grep -q 'portless proxy status' "$PORTLESS_MODULE"; then
	echo "portless module still uses unsupported 'portless proxy status'" >&2
	exit 1
fi

if ! grep -q 'x-portless' "$PORTLESS_MODULE"; then
	echo "portless module does not probe proxy readiness via the X-Portless header" >&2
	exit 1
fi

echo "portless module uses a real proxy readiness probe"
