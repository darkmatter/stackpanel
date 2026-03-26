#!/usr/bin/env bash
set -euo pipefail

deploy_rootdir() {
  git rev-parse --show-toplevel
}

deploy_region() {
  local requested="${1:-}"
  if [ -n "$requested" ]; then
    printf '%s\n' "$requested"
    return
  fi

  if [ -n "${AWS_REGION:-}" ]; then
    printf '%s\n' "$AWS_REGION"
    return
  fi

  printf 'us-west-2\n'
}

deploy_stage() {
  if [ -n "${STAGE:-}" ]; then
    printf '%s\n' "$STAGE"
  else
    printf 'staging\n'
  fi
}

artifact_version() {
  local rootdir="${1:-$(deploy_rootdir)}"

  if [ -n "${EC2_ARTIFACT_VERSION:-}" ]; then
    printf '%s\n' "$EC2_ARTIFACT_VERSION"
    return
  fi

  local version
  version="$(git -C "$rootdir" rev-parse --short=12 HEAD)"

  if ! git -C "$rootdir" diff --quiet --ignore-submodules HEAD -- \
    || [ -n "$(git -C "$rootdir" ls-files --others --exclude-standard)" ]; then
    local fingerprint
    fingerprint="$(
      {
        git -C "$rootdir" diff HEAD -- 2>/dev/null
        git -C "$rootdir" ls-files --others --exclude-standard -z | sort -z | xargs -0 -I{} cat "$rootdir/{}" 2>/dev/null
      } | shasum -a 256 | awk '{print substr($1, 1, 12)}'
    )"
    version="${version}-dirty-${fingerprint}"
  fi

  printf '%s\n' "$version"
}

artifact_bucket() {
  local region="$1"

  if [ -n "${EC2_ARTIFACT_BUCKET:-}" ]; then
    printf '%s\n' "$EC2_ARTIFACT_BUCKET"
    return
  fi

  local account_id
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  printf 'stackpanel-web-artifacts-%s-%s\n' "$account_id" "$region"
}

artifact_key() {
  local stage="$1"
  local version="$2"

  if [ -n "${EC2_ARTIFACT_KEY:-}" ]; then
    printf '%s\n' "$EC2_ARTIFACT_KEY"
    return
  fi

  printf 'web/%s/%s/release.tar.gz\n' "$stage" "$version"
}

artifact_s3_uri() {
  local bucket="$1"
  local key="$2"
  printf 's3://%s/%s\n' "$bucket" "$key"
}

artifact_local_dir() {
  local rootdir="$1"
  local stage="$2"
  local version="$3"
  printf '%s/.artifacts/web/%s/%s\n' "$rootdir" "$stage" "$version"
}

artifact_local_path() {
  local rootdir="$1"
  local stage="$2"
  local version="$3"
  printf '%s/release.tar.gz\n' "$(artifact_local_dir "$rootdir" "$stage" "$version")"
}

ensure_artifact_dir() {
  local rootdir="$1"
  local stage="$2"
  local version="$3"
  mkdir -p "$(artifact_local_dir "$rootdir" "$stage" "$version")"
}

ensure_artifact_bucket() {
  local bucket="$1"
  local region="$2"

  if ! aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    if [ "$region" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$bucket" --region "$region"
    else
      aws s3api create-bucket \
        --bucket "$bucket" \
        --region "$region" \
        --create-bucket-configuration "LocationConstraint=${region}"
    fi
  fi

  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    >/dev/null

  aws s3api put-bucket-encryption \
    --bucket "$bucket" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    >/dev/null
}
