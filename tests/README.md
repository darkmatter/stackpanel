# Stack Tests

Automated tests to prevent regressions in the Stackpanel Nix development shell and templates.

## Quick Start

```bash
# Run shell smoke tests
./tests/smoke-test.sh

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
  --help           Show help message
```

### Template Tests (`test-templates.sh`)

Tests all stack templates by creating temporary projects from each template and
running smoke checks on the generated projects.

**Usage:**

```bash
./tests/test-templates.sh [OPTIONS]

Options:
  --template NAME  Test only the specified template
  --keep-temp      Don't delete temporary test directories
  --help           Show help message
```

**Available Templates:**

- `default` - Full-featured flake-parts template
- `minimal` - Minimal flake-parts template

## Integration with `nix flake check`

```bash
nix flake check
nix build .#checks.aarch64-darwin.stackpanel
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
./tests/smoke-test.sh --project /path/to/your/project

cd /path/to/your/project
nix shell .#devShells.default --command which git
```

## Best Practices

1. **Run tests before committing** - Catch regressions early
2. **Test templates** - Verify user-facing templates work
3. **Add new tests** - When adding features, add corresponding tests
4. **Keep tests fast** - Tests should complete quickly
