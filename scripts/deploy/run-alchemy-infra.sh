#!/usr/bin/env bash
# ==============================================================================
# run-alchemy-infra.sh - run the local Alchemy infra step with AWS SDK parity
#
# The Nix build can run on a remote Linux builder, but Alchemy itself still runs
# locally. To keep Bun's AWS SDK on the same credential chain as the working AWS
# CLI, prefer the generated `with-aws` wrapper and enable shared-config loading.
# ==============================================================================
set -euo pipefail

ROOT_DIR="${1:?root dir required}"
APP="${2:?app required}"
STAGE="${STAGE:-staging}"
SOPS_FILE="${STACKPANEL_DEPLOY_SECRETS_FILE:-}"

if [[ -z "$SOPS_FILE" ]]; then
  SOPS_FILE="$ROOT_DIR/.stack/secrets/vars/${STAGE}.sops.yaml"
  if [[ ! -f "$SOPS_FILE" ]]; then
    SOPS_FILE="$ROOT_DIR/.stack/secrets/vars/dev.sops.yaml"
  fi
fi

if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
  export SOPS_AGE_KEY_FILE="$ROOT_DIR/.stack/keys/local.txt"
fi

export STAGE
export STACKPANEL_DEPLOYMENT_APP="$APP"
export STACKPANEL_INFRA_INPUTS="${STACKPANEL_INFRA_INPUTS:-$ROOT_DIR/.stack/profile/infra-inputs.json}"
export ALCHEMY_CI_STATE_STORE_CHECK=false
export AWS_SDK_LOAD_CONFIG=1

run_with_aws() {
  if command -v with-aws >/dev/null 2>&1; then
    with-aws "$@"
    return
  fi

  if command -v aws-creds-env >/dev/null 2>&1; then
    eval "$(aws-creds-env)"
  fi

  "$@"
}

if command -v sops >/dev/null 2>&1 && [[ -f "$SOPS_FILE" ]]; then
  ALCHEMY_PASSWORD="${ALCHEMY_PASSWORD:-$(sops -d --extract '["alchemy-password"]' "$SOPS_FILE" 2>/dev/null || echo "stackpanel-deploy-$(id -un)")}"
  export ALCHEMY_PASSWORD

  run_with_aws sops exec-env "$SOPS_FILE" "bun $ROOT_DIR/packages/infra/alchemy.run.ts"
else
  export ALCHEMY_PASSWORD="${ALCHEMY_PASSWORD:-stackpanel-deploy-$(id -un)}"
  run_with_aws bun "$ROOT_DIR/packages/infra/alchemy.run.ts"
fi
