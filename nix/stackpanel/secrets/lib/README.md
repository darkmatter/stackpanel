# Age Key Management Tools

This directory contains derivation-based tools for managing AGE keys with SOPS in Stackpanel projects.

## Overview

The age key management system provides:

- **Derivation-based tools**: Pure Nix derivations instead of shell scripts
- **Automatic key fetching**: Integration with 1Password for secure key retrieval
- **Local caching**: Keys are cached in `.keys/` to avoid repeated fetches
- **SOPS integration**: Compatible with `SOPS_AGE_KEY_CMD` environment variable

## Architecture

```
age-key-tools.nix         # Core derivations (fetchAgeKey, ageKeyCmd, etc.)
age-key-cmd.nix           # NixOS/home-manager module interface
age-key-cmd.sh            # [DEPRECATED] Old shell script - kept for reference
```

## Files

### `age-key-tools.nix`

Core derivation-based tools:

- **`fetchAgeKey`**: Fetch age keys from 1Password
- **`readAgeKeys`**: Read cached age keys from disk
- **`ageKeyCmd`**: Main command compatible with `SOPS_AGE_KEY_CMD`
- **`sopsWithAgeKey`**: Wrapped `sops` command with automatic key resolution
- **`checkAgeKeys`**: Health check tool to verify keys are available

### `age-key-cmd.nix`

Module interface for declarative configuration:

```nix
stackpanel.secrets.age-key-cmd = {
  enable = true;
  keysDir = ".keys";
  onePassword = {
    enable = true;
    account = "voytravel";
    item = "op://voy-508-shared/sops-dev";
  };
  autoSetup = true;  # Auto-configure SOPS_AGE_KEY_CMD
};
```

### `age-key-cmd.sh` [DEPRECATED]

Old shell script implementation. Kept for reference but should not be used in new code. The derivation-based approach in `age-key-tools.nix` provides:

- Better reproducibility (explicit dependencies)
- Type safety and validation
- Integration with Nix module system
- No relative path issues

## Usage

### Basic Usage (Module-based)

Enable in your `flake.nix` or module configuration:

```nix
{
  imports = [ ./nix/stackpanel/secrets/lib/age-key-cmd.nix ];

  stackpanel.secrets.age-key-cmd = {
    enable = true;
    # Optional: customize keys directory
    # keysDir = ".secrets/keys";
  };
}
```

This automatically:
1. Adds age key tools to your devShell
2. Sets `SOPS_AGE_KEY_CMD` environment variable
3. Adds `.keys/` to `.gitignore`
4. Provides helper commands: `age:fetch`, `age:check`

### Direct Usage (Package-based)

If you need the tools without the module system:

```nix
{
  ageKeyTools = pkgs.callPackage ./nix/stackpanel/secrets/lib/age-key-tools.nix {
    keysDir = ".keys";
    opAccount = "voytravel";
    opItem = "op://voy-508-shared/sops-dev";
  };

  devShells.default = pkgs.mkShell {
    packages = [ ageKeyTools.ageKeyCmd ];
    shellHook = ''
      export SOPS_AGE_KEY_CMD="${ageKeyTools.ageKeyCmd}/bin/age-key-cmd"
    '';
  };
}
```

### Command Line Usage

#### Fetch keys from 1Password

```bash
# Using module helper
age:fetch

# Or directly
fetch-age-key
```

#### Check available keys

```bash
# Using module helper
age:check

# Or directly
check-age-keys
```

#### Use with SOPS

```bash
# Automatic (if module is enabled)
sops .stack/secrets/dev/web.sops.yaml

# Manual
SOPS_AGE_KEY_CMD=age-key-cmd sops .stack/secrets/dev/web.sops.yaml

# Using wrapped sops command
${ageKeyTools.sopsWithAgeKey}/bin/sops .stack/secrets/dev/web.sops.yaml
```

## Configuration

### Environment Variables

Runtime configuration (overrides build-time defaults):

- `SOPS_KEYS_DIR`: Override keys directory location
- `OP_ACCOUNT`: Override 1Password account name
- `OP_ITEM`: Override 1Password item reference
- `AGE_KEY_NAME`: Name for cached key files (default: "dev")

### Build-time Configuration

When calling `age-key-tools.nix`:

```nix
pkgs.callPackage ./age-key-tools.nix {
  keysDir = ".keys";           # Where to cache keys
  opAccount = "voytravel";     # 1Password account
  opItem = "op://vault/item";  # 1Password item reference
}
```

## 1Password Integration

### Item Format

The 1Password item should have:

- **username field**: AGE public key (`age1...`)
- **password field**: AGE private key (`AGE-SECRET-KEY-1...`)

### Authentication

Ensure you're authenticated with 1Password CLI:

```bash
op signin
```

### Security Notes

1. Keys are cached in `.keys/` directory (gitignored by default)
2. Private key files have `600` permissions
3. Keys are only fetched when not found in cache
4. Use separate 1Password items for different environments (dev/staging/prod)

## How It Works

### Key Resolution Flow

```
1. SOPS calls $SOPS_AGE_KEY_CMD
       ↓
2. age-key-cmd checks .keys/ directory
       ↓
3a. Keys found? → Return keys to SOPS
       ↓
3b. No keys? → Call fetch-age-key
       ↓
4. fetch-age-key queries 1Password CLI
       ↓
5. Cache keys to .keys/
       ↓
6. Return keys to SOPS
```

### Advantages Over Shell Script

**Old approach** (`age-key-cmd.sh`):
- Relative paths (`$(dirname $(realpath "$0"))`)
- Implicit dependencies (relies on system PATH)
- No version pinning
- Hard to test/reproduce

**New approach** (`age-key-tools.nix`):
- Absolute Nix store paths
- Explicit dependencies (coreutils, findutils, etc.)
- Reproducible builds
- Module system integration
- Type-safe configuration

## Troubleshooting

### "No age keys available"

```bash
# Check if 1Password CLI is installed and authenticated
op signin

# Try fetching manually
fetch-age-key

# Check what keys exist
check-age-keys
```

### "1Password CLI not found"

Install 1Password CLI:

```bash
# macOS
brew install 1password-cli

# Or add to your Nix configuration
packages = [ pkgs._1password ];
```

### Keys not being used by SOPS

```bash
# Verify environment variable is set
echo $SOPS_AGE_KEY_CMD

# Test key command manually
$SOPS_AGE_KEY_CMD

# Should output AGE-SECRET-KEY-1...
```

### Permission denied on .keys/

```bash
# Reset permissions
chmod 700 .keys
chmod 600 .keys/*.age
```

## Migration Guide

If you're currently using `age-key-cmd.sh`:

1. **Enable the module** in your configuration:
   ```nix
   stackpanel.secrets.age-key-cmd.enable = true;
   ```

2. **Remove manual SOPS_AGE_KEY_CMD exports** from shell scripts

3. **Update 1Password references** if needed:
   ```nix
   stackpanel.secrets.age-key-cmd.onePassword = {
     account = "your-account";
     item = "op://your-vault/your-item";
   };
   ```

4. **Test the new setup**:
   ```bash
   age:check  # Should show your keys or fetch them
   ```

5. **Remove old shell script references** once verified

## Development

### Testing the Tools

```bash
# Test key fetching
SOPS_KEYS_DIR=/tmp/test-keys fetch-age-key

# Test key reading
SOPS_KEYS_DIR=/tmp/test-keys age-key-cmd

# Test with SOPS
SOPS_KEYS_DIR=/tmp/test-keys sops .stack/secrets/dev/web.sops.yaml
```

### Adding New Key Sources

To add support for other key sources (e.g., AWS Secrets Manager, Vault):

1. Add a new fetch function in `age-key-tools.nix`
2. Add module options in `age-key-cmd.nix`
3. Update `ageKeyCmd` to try new source

Example:

```nix
fetchFromVault = writeShellScriptBin "fetch-from-vault" ''
  # Implementation here
'';
```

## See Also

- [SOPS Documentation](https://github.com/getsops/sops)
- [age Encryption Tool](https://age-encryption.org/)
- [1Password CLI](https://developer.1password.com/docs/cli/)
- [Stackpanel Secrets Documentation](../README.md)
