#!/usr/bin/env bash
# ==============================================================================
# decrypt.sh - Decrypt a group's .enc.age file to a plaintext .age file
#
# This script requires only `sops` and `age` in PATH (no stackpanel CLI needed).
# The decrypted .age file is written next to the .enc.age file and is gitignored.
# Once decrypted, SOPS_AGE_KEY_CMD can discover it automatically.
#
# Usage:
#   ./decrypt.sh <group>          # e.g., ./decrypt.sh dev
#   ./decrypt.sh --all            # decrypt all .enc.age files
#
# Dependencies: sops, age
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$(dirname "$SCRIPT_DIR")"
RECIPIENTS_DIR="$SECRETS_DIR/recipients"

usage() {
  echo "Usage: $(basename "$0") <group> | --all"
  echo ""
  echo "Decrypt a group's .enc.age file to a plaintext .age file."
  echo "The .age file is gitignored and used for local secret resolution."
  echo ""
  echo "Arguments:"
  echo "  <group>    Group name (e.g., dev, prod)"
  echo "  --all      Decrypt all .enc.age files"
  echo ""
  echo "Available groups:"
  for f in "$RECIPIENTS_DIR"/*.enc.age 2>/dev/null; do
    [[ -f "$f" ]] || continue
    echo "  $(basename "$f" .enc.age)"
  done
  exit 1
}

decrypt_group() {
  local group="$1"
  local enc_file="$RECIPIENTS_DIR/$group.enc.age"
  local plain_file="$RECIPIENTS_DIR/$group.age"

  if [[ ! -f "$enc_file" ]]; then
    echo "Error: Encrypted key not found: $enc_file" >&2
    return 1
  fi

  if [[ -f "$plain_file" ]]; then
    echo "  $group: already decrypted (skipping)"
    return 0
  fi

  echo "  Decrypting $group..."
  if sops --config "$RECIPIENTS_DIR/.sops.yaml" --decrypt "$enc_file" > "$plain_file" 2>/dev/null; then
    chmod 600 "$plain_file"
    echo "  $group: decrypted -> $plain_file"
  else
    rm -f "$plain_file"
    echo "  $group: FAILED (do you have a matching recipient key?)" >&2
    return 1
  fi
}

[[ $# -lt 1 ]] && usage

if [[ "$1" == "--all" ]]; then
  echo "Decrypting all group keys..."
  ERRORS=0
  for enc_file in "$RECIPIENTS_DIR"/*.enc.age; do
    [[ -f "$enc_file" ]] || continue
    group=$(basename "$enc_file" .enc.age)
    decrypt_group "$group" || ((ERRORS++))
  done
  if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "Warning: $ERRORS group(s) could not be decrypted" >&2
    exit 1
  fi
elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
else
  decrypt_group "$1"
fi
