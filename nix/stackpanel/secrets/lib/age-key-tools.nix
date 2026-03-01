# ==============================================================================
# age-key-tools.nix
#
# Derivation-based tools for managing AGE keys with SOPS.
#
# Provides:
# - fetchAgeKey: Fetch age keys from 1Password or other sources
# - ageKeyCmd: Read age keys from local cache or fetch if needed
# - Configurable via environment variables (runtime) and Nix inputs (build-time)
#
# Usage:
#   sopsTools = pkgs.callPackage ./age-key-tools.nix {
#     keysDir = ".keys";  # optional, defaults to ".keys"
#     opAccount = "voytravel";  # optional 1Password account
#     opItem = "op://voy-508-shared/sops-dev";  # optional 1Password item ref
#   };
#
#   # In devShell:
#   export SOPS_AGE_KEY_CMD="${sopsTools.ageKeyCmd}/bin/age-key-cmd"
#
# Environment variables (runtime overrides):
#   SOPS_KEYS_DIR - Override keys directory location
#   OP_ACCOUNT - Override 1Password account
#   OP_ITEM - Override 1Password item reference
# ==============================================================================
{
  writeShellScriptBin,
  coreutils,
  findutils,
  _vals,
  age,
  sops,
  # Default configuration
  keysDir ? ".keys",
  valsRef ? null, # ex. "ref+awsssm://stackpanel/dev/age-key"
}:

let
  # Fetch age key from vals
  # Writes public key to KEYS_DIR/<name>.age.pub and private key to KEYS_DIR/<name>.age
  fetchAgeKey = writeShellScriptBin "fetch-age-key" ''
    set -euo pipefail

    # Runtime configuration (can be overridden by environment)
    KEYS_DIR="''${SOPS_KEYS_DIR:-${keysDir}}"
    VALS_REF_AGE_PRIV="''${VALS_REF_AGE_PRIV:-}"
    KEY_NAME="''${AGE_KEY_NAME:-dev}"

    # Check if vals CLI is available
    if ! command -v ${_vals}/bin/vals &>/dev/null; then
      echo "ERROR: vals CLI not found at ${_vals}/bin/vals" >&2
      echo "Install vals CLI or ensure it's in your system PATH" >&2
      return 1
    fi

    # Fetch keys from vals
    echo "Fetching age key from vals..." >&2
    private_key="$(${_vals}/bin/vals get "$VALS_REF_AGE_PRIV" 2>/dev/null || true)"
    public_key="$(echo "$private_key" | ${age}/bin/age-keygen -y 2>/dev/null || true)"

    if [ -z "$public_key" ] || [ -z "$private_key" ]; then
      echo "ERROR: Failed to fetch age keys from vals" >&2
      echo "ref: $VALS_REF_AGE_PRIV"
      echo "" >&2
      echo "Make sure you set the correct ref" >&2
      return 1
    fi

    # Create keys directory if it doesn't exist
    ${coreutils}/bin/mkdir -p "$KEYS_DIR"

    # Write keys to files
    echo "$public_key" > "$KEYS_DIR/$KEY_NAME.age.pub"
    echo "$private_key" > "$KEYS_DIR/$KEY_NAME.age"

    # Set restrictive permissions on private key
    ${coreutils}/bin/chmod 600 "$KEYS_DIR/$KEY_NAME.age"

    echo "Successfully fetched and cached age key to $KEYS_DIR" >&2
    return 0
  '';

  # Read all age private keys from the keys directory
  # This is compatible with SOPS_AGE_KEY_CMD
  readAgeKeys = writeShellScriptBin "read-age-keys" ''
    set -euo pipefail

    KEYS_DIR="''${SOPS_KEYS_DIR:-${keysDir}}"

    if [ ! -d "$KEYS_DIR" ]; then
      return 1
    fi

    # Find and concatenate all .age files (private keys)
    keys="$(${findutils}/bin/find "$KEYS_DIR" -type f -name "*.age" -exec ${coreutils}/bin/cat {} \; 2>/dev/null || true)"

    if [ -n "$keys" ]; then
      echo "$keys"
      return 0
    fi

    return 1
  '';

  # Main age key command - compatible with SOPS_AGE_KEY_CMD
  # Tries to read cached keys, falls back to fetching from 1Password
  ageKeyCmd = writeShellScriptBin "age-key-cmd" ''
    set -euo pipefail

    KEYS_DIR="''${SOPS_KEYS_DIR:-${keysDir}}"

    # Try to read existing cached keys
    if keys="$(${readAgeKeys}/bin/read-age-keys 2>/dev/null)"; then
      echo "$keys"
      exit 0
    fi

    # No cached keys found - try to fetch from 1Password
    echo "No cached age keys found in $KEYS_DIR" >&2
    echo "Attempting to fetch from vals..." >&2

    if ${fetchAgeKey}/bin/fetch-age-key; then
      # Successfully fetched - try reading again
      if keys="$(${readAgeKeys}/bin/read-age-keys 2>/dev/null)"; then
        echo "$keys"
        exit 0
      fi
    fi

    # Failed to fetch or read keys
    echo "" >&2
    echo "ERROR: No age keys available" >&2
    echo "Options:" >&2
    echo "  1. Run: ${fetchAgeKey}/bin/fetch-age-key" >&2
    echo "  2. Manually place age private keys in: $KEYS_DIR/*.age" >&2
    echo "  3. Ensure vals CLI is available and VALS_REF_AGE_PRIV is set" >&2
    exit 1
  '';

  # Convenience wrapper for sops with automatic age key resolution
  sopsWithAgeKey = writeShellScriptBin "sops" ''
    export SOPS_AGE_KEY_CMD="${ageKeyCmd}/bin/age-key-cmd"
    exec ${sops}/bin/sops "$@"
  '';

  # Check if age keys are available (for health checks)
  checkAgeKeys = writeShellScriptBin "check-age-keys" ''
    set -euo pipefail

    KEYS_DIR="''${SOPS_KEYS_DIR:-${keysDir}}"

    echo "Checking age keys in: $KEYS_DIR"

    if [ ! -d "$KEYS_DIR" ]; then
      echo "❌ Keys directory does not exist"
      exit 1
    fi

    key_count=$(${findutils}/bin/find "$KEYS_DIR" -type f -name "*.age" 2>/dev/null | ${coreutils}/bin/wc -l | ${coreutils}/bin/tr -d ' ')

    if [ "$key_count" -eq 0 ]; then
      echo "❌ No age keys found"
      echo ""
      echo "Run this to fetch keys:"
      echo "  ${fetchAgeKey}/bin/fetch-age-key"
      exit 1
    fi

    echo "✓ Found $key_count age key(s)"

    # List public keys if available
    if pub_keys=$(${findutils}/bin/find "$KEYS_DIR" -type f -name "*.age.pub" 2>/dev/null); then
      if [ -n "$pub_keys" ]; then
        echo ""
        echo "Public keys:"
        echo "$pub_keys" | while read -r pub_file; do
          name=$(${coreutils}/bin/basename "$pub_file" .age.pub)
          key=$(${coreutils}/bin/cat "$pub_file")
          echo "  $name: $key"
        done
      fi
    fi

    exit 0
  '';

in
{
  inherit fetchAgeKey readAgeKeys ageKeyCmd sopsWithAgeKey checkAgeKeys;

  # Expose configuration for debugging
  config = {
    inherit keysDir valsRef;
  };
}
