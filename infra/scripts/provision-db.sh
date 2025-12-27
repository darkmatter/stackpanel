#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Required command not found: $1" >&2
    exit 1
  fi
}

sanitize_ident() {
  # Postgres identifiers: keep alnum + underscore, collapse others to underscore, trim to 63 chars.
  # Also ensure it doesn't start with a digit.
  local s="${1:-}"
  s="$(echo "$s" | tr -c 'a-zA-Z0-9_' '_' | cut -c1-63)"
  if [[ "$s" =~ ^[0-9] ]]; then
    s="sp_${s}"
    s="$(echo "$s" | cut -c1-63)"
  fi
  echo "$s"
}

gen_password() {
  # Generate a URL-safe-ish password (no quotes/spaces) for easy JSON embedding.
  # 32 chars from base64 output with non-alnum stripped.
  local pw
  pw="$(openssl rand -base64 48 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-32)"
  if [[ -z "$pw" ]]; then
    echo "❌ Failed to generate password" >&2
    exit 1
  fi
  echo "$pw"
}

main() {
  require_cmd psql
  require_cmd pg_restore
  require_cmd openssl

  : "${PGHOST:?PGHOST is required}"
  : "${PGUSER:?PGUSER is required}"
  : "${PGPASSWORD:?PGPASSWORD is required}"

  local pgport="${PGPORT:-5432}"
  local sslmode="${PGSSLMODE:-prefer}"

  : "${DB_NAME:?DB_NAME is required}"
  DB_NAME="$(sanitize_ident "$DB_NAME")"

  if [[ -n "${DB_USER:-}" ]]; then
    DB_USER="$(sanitize_ident "$DB_USER")"
  else
    DB_USER="$(sanitize_ident "sp_${DB_NAME}")"
  fi

  local db_password
  db_password="$(gen_password)"

  echo "::add-mask::$db_password"

  export PGPASSWORD

  echo "🔧 Provisioning database '$DB_NAME' on $PGHOST:$pgport (as $PGUSER)"

  # Ensure role exists (and set password).
  psql \
    -h "$PGHOST" -p "$pgport" -U "$PGUSER" -d postgres \
    -v ON_ERROR_STOP=1 \
    -v db_user="$DB_USER" \
    -v db_password="$db_password" \
    <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'db_user') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password');
  END IF;
END $$;
SQL

  # Ensure DB doesn't already exist.
  local exists
  exists="$(psql -h "$PGHOST" -p "$pgport" -U "$PGUSER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'")"
  if [[ "$exists" == "1" ]]; then
    echo "❌ Database already exists: $DB_NAME" >&2
    exit 1
  fi

  # Create DB owned by the new role.
  psql -h "$PGHOST" -p "$pgport" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 -c \
    "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"

  # Optionally restore a snapshot from S3/MinIO.
  if [[ -n "${SNAPSHOT_URI:-}" ]]; then
    require_cmd aws
    export AWS_EC2_METADATA_DISABLED="true"

    tmp="$(mktemp -t stackpanel-seed.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT

    echo "⬇️  Downloading snapshot: $SNAPSHOT_URI"
    aws_args=(s3 cp "$SNAPSHOT_URI" "$tmp")
    if [[ -n "${S3_ENDPOINT_URL:-}" ]]; then
      aws_args+=(--endpoint-url "$S3_ENDPOINT_URL")
    fi
    aws "${aws_args[@]}"

    echo "🗃️  Restoring snapshot into '$DB_NAME' (setting role to '$DB_USER')"
    pg_restore \
      --no-owner \
      --no-privileges \
      --role="$DB_USER" \
      -h "$PGHOST" -p "$pgport" -U "$PGUSER" -d "$DB_NAME" \
      "$tmp"
  fi

  local conn="postgresql://${DB_USER}:${db_password}@${PGHOST}:${pgport}/${DB_NAME}?sslmode=${sslmode}"
  echo "::add-mask::$conn"

  cat > db_connection.json <<JSON
{
  "host": "${PGHOST}",
  "port": ${pgport},
  "database": "${DB_NAME}",
  "user": "${DB_USER}",
  "password": "${db_password}",
  "sslmode": "${sslmode}",
  "connection_string": "${conn}"
}
JSON

  echo "✅ Provisioned database '$DB_NAME' (artifact: db_connection.json)"
}

main "$@"




