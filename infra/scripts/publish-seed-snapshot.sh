#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Required command not found: $1" >&2
    exit 1
  fi
}

main() {
  require_cmd pg_dump
  require_cmd aws

  : "${SOURCE_DATABASE_URL:?SOURCE_DATABASE_URL is required}"
  : "${SNAPSHOT_URI:?SNAPSHOT_URI is required (e.g. s3://bucket/path.dump)}"

  export AWS_EC2_METADATA_DISABLED="true"

  tmp="$(mktemp -t stackpanel-seed.XXXXXX)"
  trap 'rm -f "$tmp"' EXIT

  echo "🧪 Creating seed snapshot from source DB..."
  pg_dump -Fc --no-owner --no-privileges "$SOURCE_DATABASE_URL" -f "$tmp"

  echo "⬆️  Uploading snapshot to: $SNAPSHOT_URI"
  aws_args=(s3 cp "$tmp" "$SNAPSHOT_URI")
  if [[ -n "${S3_ENDPOINT_URL:-}" ]]; then
    aws_args+=(--endpoint-url "$S3_ENDPOINT_URL")
  fi
  aws "${aws_args[@]}"

  echo "✅ Published seed snapshot: $SNAPSHOT_URI"
}

main "$@"




