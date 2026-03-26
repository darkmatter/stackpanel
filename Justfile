# Stackpanel Development Commands
# Install just: https://github.com/casey/just
#
# Set NIX_SKIP_DEVELOP=1 to bypass the `nix develop --impure -c` wrapper and
# run commands directly in the current shell (useful inside CI or a devshell).

rootdir := `git rev-parse --show-toplevel`

# Optional nix develop wrapper — skipped when NIX_SKIP_DEVELOP=1

nix-run := if env("NIX_SKIP_DEVELOP", "") != "" { "" } else { "nix develop --impure -c " }

# Default recipe — list available recipes
default:
    @just --list

# ── Tests ──────────────────────────────────────────────────────────────────────

# Run all tests
test *args:
    ./tests/smoke-test.sh --both {{ args }}
    ./tests/test-templates.sh {{ args }}

# Run smoke tests against both devenv and native shells
test-smoke *args:
    ./tests/smoke-test.sh --both {{ args }}

# Run smoke tests against the devenv shell only
test-devenv *args:
    ./tests/smoke-test.sh --devenv {{ args }}

# Run smoke tests against the native shell only
test-native *args:
    ./tests/smoke-test.sh --native {{ args }}

# Test all project templates
test-templates *args:
    ./tests/test-templates.sh {{ args }}

# Test a specific project template
test-template name *args:
    ./tests/test-templates.sh --template {{ name }} {{ args }}

# ── Nix ────────────────────────────────────────────────────────────────────────

# Run nix flake check
check *args:
    nix flake check --impure {{ args }}

# Enter the devenv shell
dev:
    nix develop --impure

# Enter the native shell (skips devenv activation)
dev-native:
    SKIP_DEVENV=true nix develop --impure

# Wipe the nix-direnv cache and reload the environment
clean-cache:
    rm -rf ~/.cache/nix-direnv
    direnv reload

# List packages exposed by the devshell
show-packages:
    nix shell .#devShells.aarch64-darwin.default --impure --command bash -c 'echo $PATH | tr ":" "\n" | grep /nix/store'

# ── Web Deploy (EC2 / AL2023) ──────────────────────────────────────────────────

# Build the web release tarball (does not upload)
deploy-build-artifact region='us-west-2' *args:
    {{ nix-run }}bash "{{ rootdir }}/scripts/deploy/build-artifact.sh" "{{ region }}" {{ args }}

# Upload the web release tarball to S3 (does not deploy)
deploy-publish-artifact region='us-west-2' *args:
    {{ nix-run }}bash "{{ rootdir }}/scripts/deploy/publish-artifact.sh" "{{ region }}" {{ args }}

# Run the Alchemy infrastructure step for the web app
deploy-alchemy region='us-west-2':
    #!/usr/bin/env bash
    set -euo pipefail

    ROOTDIR="{{ rootdir }}"
    REGION="{{ region }}"
    STAGE="${STAGE:-staging}"
    ALCHEMY_ENTRY="${ROOTDIR}/packages/infra/alchemy.run.ts"
    LOCAL_AGE_KEY_FILE="${ROOTDIR}/.stack/keys/local.txt"

    SECRETS_FILE="${STACKPANEL_DEPLOY_SECRETS_FILE:-}"
    if [ -z "$SECRETS_FILE" ]; then
      STAGE_SECRETS="${ROOTDIR}/.stack/secrets/vars/${STAGE}.sops.yaml"
      DEFAULT_SECRETS="${ROOTDIR}/.stack/secrets/vars/dev.sops.yaml"
      SECRETS_FILE="$([ -f "$STAGE_SECRETS" ] && echo "$STAGE_SECRETS" || echo "$DEFAULT_SECRETS")"
    fi

    if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_CMD:-}" ] && [ -f "$LOCAL_AGE_KEY_FILE" ]; then
      export SOPS_AGE_KEY_FILE="$LOCAL_AGE_KEY_FILE"
    fi

    SOPS_BIN="$(command -v sops 2>/dev/null || direnv exec "$ROOTDIR" bash -lc 'command -v sops')"

    if [ -z "${ALCHEMY_PASSWORD:-}" ]; then
      ALCHEMY_PASSWORD="$("$SOPS_BIN" -d --extract '["alchemy-password"]' "$SECRETS_FILE" 2>/dev/null || echo "stackpanel-deploy-$(id -un)")"
    fi

    echo "==> Running Alchemy deploy"
    echo "    Region:  ${REGION}"
    echo "    Stage:   ${STAGE}"
    echo "    Secrets: ${SECRETS_FILE}"

    "$SOPS_BIN" exec-env "$SECRETS_FILE" \
      "env \
        ALCHEMY_CI_STATE_STORE_CHECK=false \
        ALCHEMY_PASSWORD=$(printf '%q' "$ALCHEMY_PASSWORD") \
        AWS_REGION=$(printf '%q' "$REGION") \
        STACKPANEL_INFRA_INPUTS=$(printf '%q' "$ROOTDIR/.stack/profile/infra-inputs.json") \
        STACKPANEL_DEPLOYMENT_APP=web \
        STAGE=$(printf '%q' "$STAGE") \
        EC2_ARTIFACT_BUCKET=$(printf '%q' "${EC2_ARTIFACT_BUCKET:-}") \
        EC2_ARTIFACT_KEY=$(printf '%q' "${EC2_ARTIFACT_KEY:-}") \
        EC2_ARTIFACT_VERSION=$(printf '%q' "${EC2_ARTIFACT_VERSION:-}") \
        bun $(printf '%q' "$ALCHEMY_ENTRY")"

# Full web deploy: build artifact → publish to S3 → Alchemy infra
deploy region='us-west-2':
    @just deploy-build-artifact {{ region }}
    @just deploy-publish-artifact {{ region }}
    @just deploy-alchemy {{ region }}

# Check the web deploy status on EC2 via SSM
deploy-status region='us-west-2' *args:
    {{ nix-run }}bun "{{ rootdir }}/scripts/deploy/status.ts" "{{ region }}" {{ args }}

# Tail web deploy logs from EC2 via SSM
deploy-logs region='us-west-2' lines='120' *args:
    {{ nix-run }}bun "{{ rootdir }}/scripts/deploy/logs.ts" "{{ region }}" "{{ lines }}" {{ args }}

# ── NixOS Deploy ───────────────────────────────────────────────────────────────

nixos-target := env("DEPLOY_SYSTEM", "x86_64-linux")
nixos-cache := env("CACHIX_CACHE_NAME", "darkmatter")

# Build the NixOS package for the target system (cross-build if needed)
[script]
nixos-build app='web' *args:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ nixos-target }}"
    APP="{{ app }}"
    EXTRA_ARGS="{{ args }}"
    CURRENT="$(nix eval --impure --raw --expr builtins.currentSystem)"

    if [[ "$CURRENT" != "$TARGET" ]]; then
      echo "==> Cross-building for $TARGET (current: $CURRENT)"
      echo "    Requires a Linux builder (Determinate native builder or remote builder)"
    fi

    echo "==> Building .#packages.$TARGET.$APP"
    if ! nix build ".#packages.$TARGET.$APP" --accept-flake-config $EXTRA_ARGS; then
      if [[ "$CURRENT" != "$TARGET" ]]; then
        echo ""
        echo "❌ Cross-build for $TARGET failed (building on $CURRENT)."
        echo ""
        echo "   A Linux builder is required. Options:"
        echo ""
        echo "   1. Determinate Nix Native Builder (recommended):"
        echo "        determinate-nixd auth login"
        echo "        sudo launchctl kickstart -k system/systems.determinate.nix-daemon"
        echo ""
        echo "   2. Remote builder (auto-configure):"
        echo "        configure-linux-builder"
        echo ""
        echo "   3. Deploy from CI:"
        echo "        git push && trigger the deploy-nixos GitHub Actions workflow"
        echo ""
        echo "   Verify your builder works:"
        echo "        nix build --system $TARGET nixpkgs#hello"
      fi
      exit 1
    fi

    echo "    Built: $(readlink -f result)"

# Push the built NixOS closure to Cachix
nixos-push:
    bash "{{ rootdir }}/scripts/deploy/push-cachix.sh" "{{ nixos-cache }}" ./result

# Run Alchemy infra for NixOS (provisions EC2, SG, IAM, SSM — no instance replace)
[script]
nixos-infra app='web':
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> Running Alchemy infra"
    echo "    App:   {{ app }}"
    echo "    Stage: ${STAGE:-staging}"
    bash "{{ rootdir }}/scripts/deploy/run-alchemy-infra.sh" "{{ rootdir }}" "{{ app }}"

# Apply the NixOS configuration via Colmena
[script]
nixos-apply:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Deploying via Colmena"
    if command -v colmena-apply &>/dev/null; then
      colmena-apply
    else
      colmena apply --substitute-on-destination
    fi

# Full NixOS deploy: nix build → cachix push → Alchemy infra → colmena apply
deploy-nixos app='web' *args:
    @just nixos-build {{ app }} {{ args }}
    @just nixos-push
    @just nixos-infra {{ app }}
    @just nixos-apply
