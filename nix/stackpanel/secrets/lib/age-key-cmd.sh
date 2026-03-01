#!/usr/bin/env bash
# ==============================================================================
# DEPRECATED: This shell script is deprecated in favor of age-key-tools.nix
#
# Please use the new derivation-based approach instead:
#   - age-key-tools.nix: Core derivations (fetchAgeKey, ageKeyCmd, etc.)
#   - age-key-cmd.nix: Module interface for declarative configuration
#
# See: ./README.md for migration guide
#
# This file is kept for reference only and may be removed in a future version.
# ==============================================================================

# AGE Key Command
#
# This script can be used to set the `AGE_KEY_CMD` environment variable
# when using [sops](https://github.com/getsops/sops). It:
# - checks .keys/ for a valid key
# - If not found, tries to fetch it from configured sources (e.g. from 1password using the `op` CLI tool)
# - If found, will import the key into the local age keyring and add it to ./.keys
# - If not found, will print an error message and exit with a non-zero status code
#
# `.keys` should NOT be committed to version control since it contains sensitive
# information. It should be added to .gitignore or equivalent. Only files that
# end with `.age` will be checked for decryption.
#
# NOTE: For the sake of portability, all files required to encrypt/decrypt secrets
# should be contained in the same directory. The default path for storing SOPS
# age keys (~/.config/sops/age/keys.txt) is not ideal since it would not exist
# inside of containerized environments unless expicitly mounted.
set -e

# params
SCRIPT_DIR="$(dirname $(realpath "$0"))"
KEYS_DIR="$SCRIPT_DIR/../.keys"
IS_OP_AVAILABLE=$(command -v op > /dev/null 2>&1 && echo "true" || echo "false")

# print all age keys in .keys
print_keys() {
    find "$KEYS_DIR" -type f -name "*.age" -exec cat {} \;
}

# check if .keys/ contains any valid age keys
if [ -d "$KEYS_DIR" ] && [ "$(find "$KEYS_DIR" -type f -name "*.age" -exec cat {} \;)" ]; then
    print_keys
    exit 0
fi

# Attempt to fetch the key from 1password using the `op` CLI tool. We only do this
# for the dev key
if [ "$IS_OP_AVAILABLE" = "true" ]; then
    public_key="$(op read op://voy-508-shared/sops-dev/username --account voytravel)"
    private_key="$(op read op://voy-508-shared/sops-dev/password --account voytravel)"
    if [ -n "$public_key" ] && [ -n "$private_key" ]; then
        mkdir -p "$KEYS_DIR"
        echo "$public_key" > "$KEYS_DIR/dev.age.pub"
        echo "$private_key" > "$KEYS_DIR/dev.age"
        print_keys
        exit 0
    else
        echo "1Password CLI is available but the key was not found"
        exit 1
    fi
else
    echo "1Password CLI is not available"
fi
