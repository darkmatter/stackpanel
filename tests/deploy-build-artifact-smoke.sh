#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

FAKE_ROOT="$TMPDIR/project"
mkdir -p "$FAKE_ROOT/apps/web" "$FAKE_ROOT/apps/stackpanel-go" "$FAKE_ROOT/bin"

cat > "$FAKE_ROOT/bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "rev-parse" ] && [ "\${2:-}" = "--show-toplevel" ]; then
  printf '%s\n' "$FAKE_ROOT"
  exit 0
fi
echo "unexpected git invocation: \$*" >&2
exit 1
EOF

cat > "$FAKE_ROOT/bin/stackpanel" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected stackpanel invocation: \$*" >&2
exit 1
EOF

cat > "$FAKE_ROOT/bin/go" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "run" ] && [ "\${2:-}" = "." ] && [ "\${3:-}" = "preflight" ] && [ "\${4:-}" = "run" ] && [ "\${5:-}" = "--project-root" ] && [ "\${6:-}" = "$FAKE_ROOT" ]; then
  if [ "\${STACKPANEL_FILES_PREFLIGHT_MANIFEST:-}" != "$FAKE_ROOT/preflight-manifest.json" ]; then
    echo "missing preflight manifest env var" >&2
    exit 1
  fi
  touch "$FAKE_ROOT/.preflight-called"
  exit 0
fi
echo "unexpected go invocation: \$*" >&2
exit 1
EOF

cat > "$FAKE_ROOT/bin/nix" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "eval" ]; then
  printf '%s\n' "$FAKE_ROOT/preflight-manifest.json"
  exit 0
fi
echo "unexpected nix invocation: \$*" >&2
exit 1
EOF

cat > "$FAKE_ROOT/bin/bun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "install" ]; then
  exit 0
fi
if [ "\${1:-}" = "run" ] && [ "\${2:-}" = "build:ec2" ]; then
  if [ ! -f "$FAKE_ROOT/.preflight-called" ]; then
    echo "preflight was not called before build:ec2" >&2
    exit 1
  fi
  mkdir -p .output
  printf 'artifact\n' > .output/index.txt
  exit 0
fi
if [ "\${1:-}" = "x" ] && [ "\${2:-}" = "vite" ] && [ "\${3:-}" = "build" ]; then
  if [ ! -f "$FAKE_ROOT/.preflight-called" ]; then
    echo "preflight was not called before vite build" >&2
    exit 1
  fi
  mkdir -p .output
  printf 'artifact\n' > .output/index.txt
  exit 0
fi
echo "unexpected bun invocation: \$*" >&2
exit 1
EOF

chmod +x "$FAKE_ROOT/bin/git" "$FAKE_ROOT/bin/stackpanel" "$FAKE_ROOT/bin/go" "$FAKE_ROOT/bin/nix" "$FAKE_ROOT/bin/bun"

PATH="$FAKE_ROOT/bin:$PATH" \
EC2_ARTIFACT_VERSION="test-version" \
STAGE="staging" \
bash "$REPO_ROOT/scripts/deploy/build-artifact.sh" "us-west-2"

if [ ! -f "$FAKE_ROOT/.preflight-called" ]; then
  echo "expected preflight marker to be created" >&2
  exit 1
fi

if [ ! -f "$FAKE_ROOT/.artifacts/web/staging/test-version/release.tar.gz" ]; then
  echo "expected release artifact to be created" >&2
  exit 1
fi

echo "deploy build artifact smoke test passed"
