#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=/Users/cm/.mux/src/stackpanel/stackpanel-71sc
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$PROJECT_ROOT/.stack/secrets/vars" ]]; then
  SECRETS_DIR="$PROJECT_ROOT/.stack/secrets"
else
  SECRETS_DIR="$(dirname "$SCRIPT_DIR")"
fi
VARS_DIR="$SECRETS_DIR/vars"
SOPS_CONFIG="$SECRETS_DIR/.sops.yaml"
FILTER="${1:-}"
REKEY_COUNT=0

export SOPS_AGE_KEY_CMD="${SOPS_AGE_KEY_CMD:-/nix/store/afa15yhl99dmy3cl2z1zrkxpmvz5450v-sops-age-keys/bin/sops-age-keys}"

if [[ ! -d "$VARS_DIR" ]]; then
  echo "No vars directory found at $VARS_DIR"
  exit 0
fi

if [[ ! -f "$SOPS_CONFIG" ]]; then
  echo "Missing SOPS config: $SOPS_CONFIG" >&2
  exit 1
fi

shopt -s nullglob
for file in "$VARS_DIR"/*.sops.yaml; do
  [[ -f "$file" ]] || continue
  group="$(basename "$file" .sops.yaml)"
  if [[ -n "$FILTER" && "$group" != "$FILTER" ]]; then
    continue
  fi

  if /nix/store/a0fyqpw8gniyk666vanp8zrnwc2r6rzf-sops-3.11.0/bin/sops --config "$SOPS_CONFIG" updatekeys --yes "$file" >/dev/null; then
    echo "  $(basename "$file"): updated"
    REKEY_COUNT=$((REKEY_COUNT + 1))
  else
    echo "  $(basename "$file"): FAILED" >&2
    exit 1
  fi
done

echo ""
echo "Updated keys for $REKEY_COUNT secret file(s)"
