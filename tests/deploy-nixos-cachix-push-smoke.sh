#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HELPER="$REPO_ROOT/scripts/deploy/push-cachix.sh"
RESULT_PATH="$TMPDIR/result"
mkdir -p "$RESULT_PATH"

run_with_fake_cachix() {
  local name="$1"
  local body="$2"
  local expected_exit="$3"
  local expected_output="$4"

  local case_dir="$TMPDIR/$name"
  mkdir -p "$case_dir/bin"

  cat > "$case_dir/bin/cachix" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
  chmod +x "$case_dir/bin/cachix"

  set +e
  local output
  output="$(PATH="$case_dir/bin:$PATH" bash "$HELPER" darkmatter "$RESULT_PATH" 2>&1)"
  local status=$?
  set -e

  if [[ "$status" -ne "$expected_exit" ]]; then
    echo "expected exit $expected_exit for $name, got $status" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  if [[ "$output" != *"$expected_output"* ]]; then
    echo "expected output for $name to contain: $expected_output" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

run_with_fake_cachix \
  "missing-auth" \
  $'echo "Neither auth token nor signing key are present." >&2\nexit 1' \
  0 \
  "Skipping Cachix push"

run_with_fake_cachix \
  "other-error" \
  $'echo "unexpected cachix failure" >&2\nexit 1' \
  1 \
  "unexpected cachix failure"

run_with_fake_cachix \
  "success" \
  $'echo "pushed darkmatter"\nexit 0' \
  0 \
  "pushed darkmatter"

echo "deploy nixos cachix push smoke test passed"
