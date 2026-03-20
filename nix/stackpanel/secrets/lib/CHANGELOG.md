# Changelog: Age Key Management

## [2.0.0] - Derivation-Based Approach

### Added

- **`age-key-tools.nix`**: Core derivation-based tools for age key management
  - `fetchAgeKey`: Fetch age keys from 1Password
  - `readAgeKeys`: Read cached age keys from disk
  - `ageKeyCmd`: Main command compatible with `SOPS_AGE_KEY_CMD`
  - `sopsWithAgeKey`: Wrapped `sops` command with automatic key resolution
  - `checkAgeKeys`: Health check tool to verify keys are available

- **`age-key-cmd.nix`**: NixOS/home-manager module interface
  - Declarative configuration of age key sources
  - Automatic devShell integration
  - Auto-configuration of `SOPS_AGE_KEY_CMD`
  - Helper scripts: `age:fetch`, `age:check`
  - Automatic `.gitignore` management

- **Documentation**:
  - `README.md`: Comprehensive usage guide
  - `INTEGRATION.md`: Integration examples and patterns
  - `CHANGELOG.md`: This file

### Changed

- **Breaking**: Moved from shell script to Nix derivations
  - Old approach used relative paths and implicit dependencies
  - New approach uses absolute Nix store paths and explicit dependencies
  
- **Improved reproducibility**: All dependencies are pinned and explicit
  - `coreutils`, `findutils`, `_1password` are explicit inputs
  - No reliance on system PATH or environment

- **Better error handling**:
  - Clear error messages with actionable suggestions
  - Proper exit codes and stderr usage
  - Permission management for private keys (600)

- **Configuration model**:
  - Build-time configuration via Nix function arguments
  - Runtime configuration via environment variables
  - Module-based configuration for declarative setups

### Deprecated

- **`age-key-cmd.sh`**: Old shell script approach
  - Kept for reference only
  - Will be removed in a future version
  - See migration guide in `README.md`

### Migration Path

For users of the old `age-key-cmd.sh`:

1. Enable the new module:
   ```nix
   stack.secrets.age-key-cmd.enable = true;
   ```

2. Remove manual `SOPS_AGE_KEY_CMD` exports

3. Test with `age:check` and `age:fetch`

4. Remove references to old script

See `INTEGRATION.md` for detailed migration examples.

## [1.0.0] - Shell Script Approach

### Initial Implementation

- `age-key-cmd.sh`: Shell script for age key management
  - Checked `.keys/` for cached keys
  - Fetched from 1Password using `op` CLI
  - Used relative paths and `realpath` for directory resolution
  - Implicit dependencies on system utilities

### Issues with Shell Script Approach

1. **Portability**: Relative paths broke in different execution contexts
2. **Reproducibility**: Depended on system PATH and installed tools
3. **Maintainability**: Hard to test and version
4. **Integration**: Required manual setup in every project
5. **Type safety**: No validation of configuration
6. **Error handling**: Basic error messages without context

These issues led to the development of the derivation-based approach in v2.0.0.

## Design Principles

### V2.0 Design Goals

1. **Reproducibility**: Nix derivations ensure consistent behavior
2. **Explicitness**: All dependencies declared explicitly
3. **Modularity**: Separate concerns (fetch, read, check)
4. **Configuration**: Multiple layers (build-time, runtime, module)
5. **Integration**: First-class module system support
6. **Documentation**: Comprehensive guides and examples

### Key Improvements Over V1

| Aspect | V1 (Shell Script) | V2 (Derivations) |
|--------|------------------|------------------|
| Dependencies | Implicit (system PATH) | Explicit (Nix inputs) |
| Paths | Relative (`$(dirname ...)`) | Absolute (Nix store) |
| Configuration | Hardcoded | Multi-layer (build/runtime) |
| Integration | Manual | Module-based |
| Testing | Difficult | Easy (isolated) |
| Documentation | Inline comments | Full guides |
| Error handling | Basic | Comprehensive |
| Permissions | Manual | Automatic (600) |

## Future Enhancements

### Planned

- [ ] Support for additional secret backends (AWS Secrets Manager, Vault)
- [ ] Key rotation automation
- [ ] Multi-user key management
- [ ] Integration with agenix
- [ ] CI/CD examples and templates

### Under Consideration

- [ ] Key generation utilities
- [ ] Key backup/restore workflows
- [ ] Team onboarding automation
- [ ] Audit logging for key access
- [ ] Integration with systemd secrets

## Compatibility

### Supported Nix Versions

- Nix 2.4+ (flakes support required)
- NixOS 22.05+
- home-manager 22.05+

### Supported Platforms

- Linux (x86_64, aarch64)
- macOS (x86_64, aarch64)
- WSL2 (via native Linux support)

### 1Password CLI Versions

- 1Password CLI v2.0+
- Tested with: 2.10.0, 2.15.0, 2.20.0

### SOPS Versions

- SOPS 3.7+
- Tested with: 3.7.3, 3.8.0

## Breaking Changes

### V2.0.0

- **Removed**: Direct shell script invocation
  - Old: `./age-key-cmd.sh`
  - New: `age-key-cmd` (from Nix derivation)

- **Changed**: Environment variable behavior
  - Old: `SCRIPT_DIR` relative to shell script location
  - New: `SOPS_KEYS_DIR` with default `.keys` (configurable)

- **Changed**: 1Password configuration
  - Old: Hardcoded account/item in shell script
  - New: Configurable via Nix or environment variables

- **Added**: Required explicit dependencies
  - Must have `_1password` in Nix inputs
  - Other dependencies automatically provided

## Security Notes

### Key Storage

- Private keys cached in `.keys/` directory (gitignored by module)
- Files have 600 permissions (owner read/write only)
- No keys ever written to Nix store

### 1Password Integration

- Uses official 1Password CLI
- Requires user authentication (`op signin`)
- Keys fetched over encrypted connection
- No keys logged or cached in command history

### Best Practices

1. Use separate 1Password items for different environments
2. Rotate keys regularly (consider automation)
3. Audit `.keys/` directory permissions periodically
4. Never commit `.keys/` to version control
5. Use environment-specific key directories in CI/CD

## Acknowledgments

- Inspired by SOPS age key handling patterns
- Built on top of the excellent `age` encryption tool
- Leverages 1Password CLI for secure key distribution
- Thanks to the Nix community for derivation patterns

## References

- [SOPS Documentation](https://github.com/getsops/sops)
- [age Encryption Tool](https://age-encryption.org/)
- [1Password CLI](https://developer.1password.com/docs/cli/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [Stack Documentation](../../README.md)