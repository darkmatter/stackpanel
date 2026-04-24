#!/usr/bin/env bash
# ==============================================================================
# push-secrets.sh
#
# Decrypts the CI-accessible deploy-scope SOPS payload and pushes the
# subset of secrets the stackpanel-api Fly app needs.
#
# Reads from packages/gen/env/data/_envs/deploy.sops.json — which is
# encrypted against the GitHub Actions key (SECRETS_AGE_KEY_DEV) via the
# stackpanel codegen pipeline. Do NOT read .stack/secrets/vars/shared.sops.yaml
# here: it's encrypted only for humans and will fail in CI.
#
# Usage:
#   bash apps/api/scripts/push-secrets.sh              # push to stackpanel-api
#   FLY_APP=other bash apps/api/scripts/push-secrets.sh
#
# Requires: sops, fly CLI, SOPS_AGE_KEY (or ssh key) available locally.
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

# jq selects + renames the subset this app needs; `fly secrets import`
# reads KEY=VALUE lines. Other secrets (Cloudflare, Hetzner, Neon API key)
# are in the deploy payload too but not forwarded to this Fly app.
ENV_DUMP=$(sops -d "$DEPLOY_SOPS" | jq -r '
  {
    BETTER_AUTH_SECRET,
    BETTER_AUTH_URL: "https://api.stackpanel.com",
    AWS_ACCESS_KEY_ID: .AWS_SANDBOX_ACCESS_KEY_ID,
    AWS_SECRET_ACCESS_KEY: .AWS_SANDBOX_SECRET_ACCESS_KEY,
    AWS_REGION: "us-east-1",
    STACKPANEL_KMS_ALIAS: "alias/stackpanel-secrets",
    POLAR_ACCESS_TOKEN,
    POLAR_WEBHOOK_SECRET,
    POLAR_SUCCESS_URL: "https://local.stackpanel.com/checkout/success",
    POLAR_PRO_PRODUCT_ID_PRODUCTION,
    POLAR_FREE_PRODUCT_ID_PRODUCTION,
    CORS_ORIGIN: "https://local.stackpanel.com",
    CORS_ALLOWED_ORIGINS: "https://local.stackpanel.com,https://stackpanel.com,https://studio.stackpanel.com"
  }
  | to_entries[]
  | select(.value != null and .value != "")
  | "\(.key)=\(.value)"
')

# DATABASE_URL is intentionally NOT in the jq filter above. The deploy
# scope's POSTGRES_URL points to PlanetScale, but the api uses the Neon
# web_dev database. Set it manually once:
#   fly secrets set DATABASE_URL=postgres://... --app stackpanel-api
printf '%s\n' "$ENV_DUMP" | fly secrets import --app "$FLY_APP" --stage

echo ""
echo "✓ Pushed secrets to $FLY_APP (staged, will apply on next deploy)"
