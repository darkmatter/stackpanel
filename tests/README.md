# Stack Tests

Automated tests to prevent regressions in both devenv and native nix shell configurations.

## Quick Start

```bash
# Run all smoke tests (devenv + native)
./tests/smoke-test.sh

# Test only devenv shell
./tests/smoke-test.sh --devenv

# Test only native shell
./tests/smoke-test.sh --native

# Test all templates
./tests/test-templates.sh

# Test specific template
./tests/test-templates.sh --template minimal
```

## Test Suite

### File Mutation Regression Coverage

Source-aware file mutations are covered by targeted Go tests in
`apps/stackpanel-go/internal/fileops/apply_test.go` and
`apps/stackpanel-go/cmd/cli/nixify_test.go`.

Deployment regressions around preflight-managed app manifests are covered by
`tests/deploy-build-artifact-smoke.sh`.

These cover:

1. Backup-on-adopt for tracked files like `package.json`
2. JSON path operations (`set`, `merge`, `remove`, `append`, `appendUnique`)
3. Stale-path restoration when Stackpanel stops managing a JSON key
4. Block-managed file insertion and cleanup
5. `stackpanel nixify` generation for `json-ops`

### Smoke Tests (`smoke-test.sh`)

Tests that verify basic shell functionality:

1. **Shell builds** - Ensures the shell derivation builds without errors
2. **Packages available** - Verifies expected packages are in PATH
3. **Environment variables** - Checks required env vars are set
4. **Hooks execute** - Confirms shell hooks run without errors

**Usage:**
```bash
./tests/smoke-test.sh [OPTIONS]

Options:
  --project PATH    Test a specific project (default: current directory)
  --devenv         Test only devenv shell
  --native         Test only native nix shell
  --both           Test both shells (default)
  --help           Show help message
```

**Exit Codes:**
- `0` - All tests passed
- `1` - One or more tests failed

### Template Tests (`test-templates.sh`)

Tests all stack templates by:

1. Creating temporary projects from each template
2. Running smoke tests on the generated projects
3. Verifying both devenv and native shells work

**Usage:**
```bash
./tests/test-templates.sh [OPTIONS]

Options:
  --template NAME  Test only the specified template
  --keep-temp      Don't delete temporary test directories
  --help           Show help message
```

**Available Templates:**
- `default` - Full-featured template with all options
- `minimal` - Minimal template with basic setup
- `devenv` - Template optimized for devenv
- `native` - Template optimized for native nix

## Integration with `nix flake check`

Smoke tests are automatically run as part of `nix flake check`:

```bash
# Run all checks including smoke tests
nix flake check --impure

# Run only smoke tests
nix build .#checks.aarch64-darwin.smoke-test-devenv --impure
nix build .#checks.aarch64-darwin.smoke-test-native --impure
```

## CI/CD Integration

Add to your CI workflow:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      
      # Test current workspace
      - name: Run smoke tests
        run: ./tests/smoke-test.sh --both
      
      # Test all templates
      - name: Test templates
        run: ./tests/test-templates.sh
```

## Customizing Tests

### Adding Package Tests

Edit `smoke-test.sh` and modify the `core_packages` array:

```bash
local core_packages=(
  "git"
  "jq"
  "your-package-here"
)
```

### Adding Environment Variable Tests

Edit `smoke-test.sh` and modify the `env_vars` array:

```bash
local env_vars=(
  "STACKPANEL_ROOT"
  "YOUR_VAR_HERE"
)
```

### Testing Custom Projects

```bash
# Test a different project
./tests/smoke-test.sh --project /path/to/your/project

# Test with custom flake reference
cd /path/to/your/project
nix shell .#devShells.default --impure --command which git
```

## Troubleshooting

### Tests Fail in Devenv But Pass in Native

This usually indicates:
- Missing package merging in `devshell.nix`
- Devenv-specific configuration issues
- Module not imported in devenv context

**Fix:** Check that `stack.packages` are properly merged in `nix/internal/devshell.nix`

### Tests Fail in Native But Pass in Devenv

This usually indicates:
- Native shell missing devenv-specific packages
- Environment variable not set in native context

**Fix:** Check that native shell properly evaluates stack modules

### "Package Not Available" Errors

**Diagnosis:**
```bash
# Check what packages are actually in the shell
nix shell .#devShells.default --impure --command bash -c 'echo $PATH | tr ":" "\n"'

# Check if package is in stack config
grep -r "your-package" .stack/config.nix
```

**Fix:** Ensure package is in `stack.packages` not just `devenv.packages`

### Template Tests Fail

**Diagnosis:**
```bash
# Keep temporary directories for inspection
./tests/test-templates.sh --keep-temp

# Manually test the template
nix flake init -t .#your-template /tmp/test-template
cd /tmp/test-template
./tests/smoke-test.sh
```

## Best Practices

1. **Run tests before committing** - Catch regressions early
2. **Test both modes** - Ensure devenv and native both work
3. **Test templates** - Verify user-facing templates work
4. **Add new tests** - When adding features, add corresponding tests
5. **Keep tests fast** - Tests should complete in <1 minute

## Related Documentation

- [Development Guide](../docs/development.md)
- [Architecture](../docs/architecture.md)
- [Module System](../nix/stack/README.md)
