#!/usr/bin/env bash
# ==============================================================================
# add-recipient.sh - Add a public key to a recipient group
#
# Detects key type from prefix (AGE or SSH ED25519), writes the .pub file
# to the appropriate recipient group directory.
#
# Usage:
#   ./add-recipient.sh --key "age1..." --name alice --group team
#   ./add-recipient.sh --key "ssh-ed25519 AAAA..." --name bob --group team
#
# Dependencies: none (ssh-to-age only needed at rekey/sops-config time)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$(dirname "$SCRIPT_DIR")"
RECIPIENTS_DIR="$SECRETS_DIR/recipients"

usage() {
	echo "Usage: $(basename "$0") --key <public-key> --name <username> [--group <group>]"
	echo ""
	echo "Add a public key to a recipient group directory."
	echo ""
	echo "Options:"
	echo "  --key     Public key (age1... or ssh-ed25519 ...)"
	echo "  --name    Username (used for filename)"
	echo "  --group   Recipient group (default: team)"
	echo ""
	echo "Examples:"
	echo "  $(basename "$0") --key 'age1abc...' --name alice"
	echo "  $(basename "$0") --key 'ssh-ed25519 AAAA...' --name bob --group admins"
	exit 1
}

KEY=""
NAME=""
GROUP="team"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--key | -k)
		KEY="$2"
		shift 2
		;;
	--name | -n)
		NAME="$2"
		shift 2
		;;
	--group | -g)
		GROUP="$2"
		shift 2
		;;
	-h | --help)
		usage
		;;
	*)
		echo "Unknown option: $1" >&2
		usage
		;;
	esac
done

if [[ -z "$KEY" ]]; then
	echo "Error: --key is required" >&2
	usage
fi

if [[ -z "$NAME" ]]; then
	echo "Error: --name is required" >&2
	usage
fi

# Detect key type and determine file extension
case "$KEY" in
age1*)
	EXT="age.pub"
	;;
ssh-ed25519*)
	EXT="ed25519.pub"
	;;
ssh-rsa*)
	echo "Error: RSA keys are not supported by age. Use an ED25519 key instead." >&2
	exit 1
	;;
*)
	echo "Error: Unrecognized key type. Expected age1... or ssh-ed25519 ..." >&2
	exit 1
	;;
esac

# Create group directory if needed
GROUP_DIR="$RECIPIENTS_DIR/$GROUP"
mkdir -p "$GROUP_DIR"

# Write the key file
OUTPUT_FILE="$GROUP_DIR/$NAME.$EXT"
echo "$KEY" >"$OUTPUT_FILE"

echo "Added recipient: $OUTPUT_FILE"
echo "  Key type: $EXT"
echo "  Group: $GROUP"
echo ""
echo "Next steps:"
echo "  1. Commit: git add $OUTPUT_FILE"
echo "  2. Push to trigger the rekey workflow (or run bin/rekey.sh locally)"
