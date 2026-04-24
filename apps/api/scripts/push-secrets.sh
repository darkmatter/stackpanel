#!/usr/bin/env bash
# ==============================================================================
# push-secrets.sh
#
# Decrypts the shared SOPS file and pushes the subset of secrets the
# stackpanel-api Fly app needs. Designed for one-shot use after a sops
# rotation or when first bootstrapping the app.
#
# Usage:
#   bash apps/api/scripts/push-secrets.sh              # push to stackpanel-api
#   FLY_APP=other bash apps/api/scripts/push-secrets.sh
#
# Requires: sops, fly CLI, AGE key available for decryption.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SOPS_FILE="${REPO_ROOT}/.stack/secrets/vars/shared.sops.yaml"
FLY_APP="${FLY_APP:-stackpanel-api}"

if [[ ! -f "$SOPS_FILE" ]]; then
  echo "sops file not found: $SOPS_FILE" >&2
  exit 1
fi

# sops exec-env takes ONE command string — it passes it to `sh -c`. We
# emit KEY=VALUE lines via a heredoc that references the decrypted env
# vars (sops exposes them as lowercase, matching the YAML key names).
ENV_DUMP=$(sops exec-env "$SOPS_FILE" 'cat <<EOF
BETTER_AUTH_SECRET=$better_auth_secret
BETTER_AUTH_URL=https://api.stackpanel.com
AWS_ACCESS_KEY_ID=$aws_sandbox_access_key_id
AWS_SECRET_ACCESS_KEY=$aws_sandbox_secret_access_key
AWS_REGION=us-east-1
STACKPANEL_KMS_ALIAS=alias/stackpanel-secrets
POLAR_ACCESS_TOKEN=$polar_access_token
POLAR_WEBHOOK_SECRET=$polar_webhook_secret
POLAR_SUCCESS_URL=https://local.stackpanel.com/checkout/success
POLAR_PRO_PRODUCT_ID_PRODUCTION=$polar_pro_product_id_production
POLAR_FREE_PRODUCT_ID_PRODUCTION=$polar_free_product_id_production
CORS_ORIGIN=https://local.stackpanel.com
CORS_ALLOWED_ORIGINS=https://local.stackpanel.com,https://stackpanel.com,https://studio.stackpanel.com
EOF')

printf '%s\n' "$ENV_DUMP" | fly secrets import --app "$FLY_APP" --stage

echo ""
echo "✓ Pushed secrets to $FLY_APP (staged, will apply on next deploy)"
echo ""
echo "Next: manually set DATABASE_URL with the Neon connection string."
echo "  fly secrets set DATABASE_URL='postgresql://...' --app $FLY_APP"
