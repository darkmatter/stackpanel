#!/usr/bin/env bash
# ==============================================================================
# rotate.sh - Generate a new AGE keypair for a group and re-encrypt
#
# This script:
#   1. Archives the old private key to recipients/.archive/
#   2. Generates a new AGE keypair
#   3. Writes the new .age and .age.pub files
#   4. Encrypts the new private key as .enc.age (to all recipients)
#   5. Re-encrypts vars/<group>.sops.yaml to the new key
#
# After running this script, update the age-pub in config.nix.
#
# Usage:
#   ./rotate.sh <group>          # e.g., ./rotate.sh prod
#
# Dependencies: age, sops
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$(dirname "$SCRIPT_DIR")"
RECIPIENTS_DIR="$SECRETS_DIR/recipients"
VARS_DIR="$SECRETS_DIR/vars"
ARCHIVE_DIR="$RECIPIENTS_DIR/.archive"

usage() {
	echo "Usage: $(basename "$0") <group>"
	echo ""
	echo "Generate a new AGE keypair for a group and re-encrypt everything."
	echo ""
	echo "Steps performed:"
	echo "  1. Archive old private key to recipients/.archive/"
	echo "  2. Generate new AGE keypair"
	echo "  3. Encrypt new private key as .enc.age"
	echo "  4. Re-encrypt vars/<group>.sops.yaml to new key"
	echo ""
	echo "After rotation, update age-pub in .stackpanel/config.nix"
	exit 1
}

[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && usage

GROUP="$1"
OLD_AGE="$RECIPIENTS_DIR/$GROUP.age"
OLD_ENC="$RECIPIENTS_DIR/$GROUP.enc.age"
VARS_FILE="$VARS_DIR/$GROUP.sops.yaml"

# Verify the group exists (has an .enc.age or .age file)
if [[ ! -f "$OLD_AGE" && ! -f "$OLD_ENC" ]]; then
	echo "Error: No key found for group '$GROUP'" >&2
	echo "Expected: $OLD_AGE or $OLD_ENC" >&2
	exit 1
fi

# Step 1: Archive old key
if [[ -f "$OLD_AGE" ]]; then
	OLD_PUB=$(age-keygen -y "$OLD_AGE" 2>/dev/null || true)
	if [[ -n "$OLD_PUB" ]]; then
		PREFIX="${OLD_PUB:0:8}"
		SUFFIX="${OLD_PUB: -8}"
		ARCHIVE_NAME="$GROUP-${PREFIX}-${SUFFIX}.age"
		mkdir -p "$ARCHIVE_DIR"
		mv "$OLD_AGE" "$ARCHIVE_DIR/$ARCHIVE_NAME"
		echo "Archived old key as recipients/.archive/$ARCHIVE_NAME"
	fi
fi

# Step 2: Generate new keypair
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

age-keygen -o "$TMPDIR/key.txt" 2>/dev/null
NEW_PRIVATE=$(cat "$TMPDIR/key.txt")
NEW_PUBLIC=$(age-keygen -y "$TMPDIR/key.txt")

echo ""
echo "New public key: $NEW_PUBLIC"
echo ""

# Step 3: Write new files
echo "$NEW_PUBLIC" >"$RECIPIENTS_DIR/$GROUP.age.pub"
cp "$TMPDIR/key.txt" "$RECIPIENTS_DIR/$GROUP.age"
chmod 600 "$RECIPIENTS_DIR/$GROUP.age"
echo "Saved new key pair:"
echo "  Public:  $RECIPIENTS_DIR/$GROUP.age.pub"
echo "  Private: $RECIPIENTS_DIR/$GROUP.age (gitignored)"

# Step 4: Encrypt new private key as .enc.age
if [[ -f "$RECIPIENTS_DIR/.sops.yaml" ]]; then
	echo "$NEW_PRIVATE" >"$TMPDIR/plain.txt"
	if sops --config "$RECIPIENTS_DIR/.sops.yaml" \
		--filename-override "$OLD_ENC" \
		--encrypt --input-type binary --output-type binary \
		"$TMPDIR/plain.txt" >"$TMPDIR/encrypted.bin" 2>/dev/null; then
		mv "$TMPDIR/encrypted.bin" "$OLD_ENC"
		echo "  Encrypted: $OLD_ENC"
	else
		echo "Warning: Could not encrypt .enc.age (recipients/.sops.yaml may need updating)" >&2
		echo "Run ./rekey.sh to regenerate it" >&2
	fi
else
	echo "Warning: recipients/.sops.yaml not found. Run ./rekey.sh first." >&2
fi

# Step 5: Re-encrypt vars file if it exists
if [[ -f "$VARS_FILE" ]]; then
	echo ""
	echo "Re-encrypting $VARS_FILE to new key..."
	# Decrypt with old key (which is now in .archive or still available via sops-age-keys)
	if PLAIN=$(sops --decrypt "$VARS_FILE" 2>/dev/null); then
		echo "$PLAIN" >"$TMPDIR/vars-plain.yaml"
		# Re-encrypt to new key
		if sops --encrypt --age "$NEW_PUBLIC" "$TMPDIR/vars-plain.yaml" >"$TMPDIR/vars-enc.yaml" 2>/dev/null; then
			mv "$TMPDIR/vars-enc.yaml" "$VARS_FILE"
			echo "  Re-encrypted: $VARS_FILE"
		else
			echo "Warning: Could not re-encrypt $VARS_FILE" >&2
		fi
	else
		echo "Warning: Could not decrypt $VARS_FILE (skipping re-encryption)" >&2
	fi
fi

echo ""
echo "Next steps:"
echo "  1. Update .stackpanel/config.nix:"
echo ""
echo "     stackpanel.secrets.groups.$GROUP.age-pub = \"$NEW_PUBLIC\";"
echo ""
echo "  2. Commit changes: git add $RECIPIENTS_DIR/$GROUP.* $VARS_FILE"
echo "  3. Re-enter devshell to pick up the new key"
