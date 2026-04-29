#!/usr/bin/env bash
# ==============================================================================
# push-secrets.sh
#
# Decrypts the CI-accessible deploy-scope SOPS payload as dotenv format
# and pushes the subset of secrets the stackpanel-api Fly app needs.
#
# Reads from packages/gen/env/data/_envs/deploy.sops.json — which is
# encrypted against the GitHub Actions key (SECRETS_AGE_KEY_DEV) via the
# stackpanel codegen pipeline. Do NOT read .stack/secrets/vars/shared.sops.yaml
# here: it's encrypted only for humans and will fail in CI.
#
# DATABASE_URL is NOT set here — the deploy scope's POSTGRES_URL points at
# PlanetScale but the api uses Neon web_dev. Set it once manually:
#   fly secrets set DATABASE_URL='postgres://...' --app stackpanel-api
#
# Usage:
#   bash apps/api/scripts/push-secrets.sh              # push to stackpanel-api
#   FLY_APP=other bash apps/api/scripts/push-secrets.sh
#
# Requires: sops (3.9+ for --output-type dotenv), fly CLI, a key that
# decrypts the deploy payload (SOPS_AGE_KEY, ssh key, etc.).
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
DEPLOY_SOPS="${REPO_ROOT}/packages/gen/env/data/_envs/deploy.sops.json"
FLY_APP="${FLY_APP:-stackpanel-api}"

if [[ ! -f "$DEPLOY_SOPS" ]]; then
  echo "deploy sops payload not found: $DEPLOY_SOPS" >&2
  echo "run \`nix develop --impure\` once to regenerate it." >&2
  exit 1
fi

# dotenv output gives us KEY=VALUE lines directly. We select + rename a
# subset (AWS_SANDBOX_* → AWS_*) and append fixed non-secret env below.
SOURCE_ENV=$(sops --output-type dotenv -d "$DEPLOY_SOPS")

{
  # Secrets from the deploy scope — renamed where the Fly app expects
  # the unprefixed AWS var name.
  echo "$SOURCE_ENV" | grep -E '^(BETTER_AUTH_SECRET|POLAR_ACCESS_TOKEN|POLAR_WEBHOOK_SECRET|POLAR_PRO_PRODUCT_ID_PRODUCTION|POLAR_FREE_PRODUCT_ID_PRODUCTION)='
  echo "$SOURCE_ENV" | grep -E '^AWS_SANDBOX_ACCESS_KEY_ID=' | sed 's/^AWS_SANDBOX_/AWS_/'
  echo "$SOURCE_ENV" | grep -E '^AWS_SANDBOX_SECRET_ACCESS_KEY=' | sed 's/^AWS_SANDBOX_/AWS_/'

  # Fixed non-secret env — same across deploys of the production stage.
  cat <<EOF
BETTER_AUTH_URL=https://api.stackpanel.com
AWS_REGION=us-east-1
STACKPANEL_KMS_ALIAS=alias/stackpanel-secrets
POLAR_SUCCESS_URL=https://local.stackpanel.com/checkout/success
CORS_ORIGIN=https://local.stackpanel.com
CORS_ALLOWED_ORIGINS=https://local.stackpanel.com,https://stackpanel.com,https://studio.stackpanel.com
EOF
} | "${FLY_BIN:-flyctl}" secrets import --app "$FLY_APP" --stage

echo "✓ Pushed secrets to $FLY_APP (staged, will apply on next deploy)"
