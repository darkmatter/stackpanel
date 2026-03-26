#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

PROJECT_ROOT="$TMPDIR/project"
HELPER="$REPO_ROOT/scripts/deploy/run-alchemy-infra.sh"
mkdir -p "$PROJECT_ROOT/.stack/secrets/vars" "$PROJECT_ROOT/.stack/keys" "$PROJECT_ROOT/.stack/profile" "$PROJECT_ROOT/bin"
printf 'dummy' > "$PROJECT_ROOT/.stack/secrets/vars/staging.sops.yaml"
printf 'dummy' > "$PROJECT_ROOT/.stack/keys/local.txt"
printf '{}' > "$PROJECT_ROOT/.stack/profile/infra-inputs.json"

cat > "$PROJECT_ROOT/bin/with-aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export TEST_WITH_AWS_CALLED=1
exec "$@"
EOF

cat > "$PROJECT_ROOT/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-d" ]]; then
  printf 'test-password\n'
  exit 0
fi
if [[ "${1:-}" == "exec-env" ]]; then
  shift 2
  exec bash -c "$1"
fi
echo "unexpected sops invocation: $*" >&2
exit 1
EOF

cat > "$PROJECT_ROOT/bin/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${TEST_WITH_AWS_CALLED:-}" != "1" ]]; then
  echo "bun was not executed under with-aws" >&2
  exit 1
fi
if [[ "${AWS_SDK_LOAD_CONFIG:-}" != "1" ]]; then
  echo "missing AWS_SDK_LOAD_CONFIG" >&2
  exit 1
fi
if [[ "${STACKPANEL_DEPLOYMENT_APP:-}" != "web" ]]; then
  echo "missing STACKPANEL_DEPLOYMENT_APP" >&2
  exit 1
fi
if [[ "${STAGE:-}" != "staging" ]]; then
  echo "missing STAGE" >&2
  exit 1
fi
if [[ "${ALCHEMY_PASSWORD:-}" != "test-password" ]]; then
  echo "missing ALCHEMY_PASSWORD" >&2
  exit 1
fi
if [[ "${STACKPANEL_INFRA_INPUTS:-}" != *".stack/profile/infra-inputs.json" ]]; then
  echo "missing STACKPANEL_INFRA_INPUTS" >&2
  exit 1
fi
exit 0
EOF

chmod +x "$PROJECT_ROOT/bin/with-aws" "$PROJECT_ROOT/bin/sops" "$PROJECT_ROOT/bin/bun"

PATH="$PROJECT_ROOT/bin:$PATH" \
STAGE="staging" \
bash "$HELPER" "$PROJECT_ROOT" "web"

cat > "$PROJECT_ROOT/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-d" ]]; then
  exit 1
fi
if [[ "${1:-}" == "exec-env" ]]; then
  shift 2
  exec bash -c "$1"
fi
echo "unexpected sops invocation: $*" >&2
exit 1
EOF
chmod +x "$PROJECT_ROOT/bin/sops"

cat > "$PROJECT_ROOT/bin/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${TEST_WITH_AWS_CALLED:-}" != "1" ]]; then
  echo "bun was not executed under with-aws" >&2
  exit 1
fi
expected_password="stackpanel-deploy-$(id -un)"
if [[ "${ALCHEMY_PASSWORD:-}" != "$expected_password" ]]; then
  echo "unexpected fallback ALCHEMY_PASSWORD: ${ALCHEMY_PASSWORD:-}" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$PROJECT_ROOT/bin/bun"

PATH="$PROJECT_ROOT/bin:$PATH" \
STAGE="staging" \
bash "$HELPER" "$PROJECT_ROOT" "web"

echo "deploy nixos infra aws smoke test passed"
