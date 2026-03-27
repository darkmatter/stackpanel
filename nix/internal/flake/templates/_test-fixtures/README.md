# Test Fixtures

These fixtures are used for testing stack modules in CI. They are **not** meant for `nix flake init`.

## Notes

- Fixtures use SSH URLs (`git+ssh://git@github.com/darkmatter/stack`) which require SSH access to the repo
- Initial runs are slow due to fetching nixpkgs, flake-parts, etc. Subsequent runs use cached inputs
- Use `--no-write-lock-file` to avoid modifying the fixture's lock file
- Override `stack` input with local path for development: `--override-input stack path:.`

## Scenarios

| Fixture | Description | Tests |
|---------|-------------|-------|
| `basic` | Minimal config, no apps | Core evaluation, basic options |
| `with-oxlint` | OxLint enabled with web app | Linting module, file generation, scripts |
| `full-stack` | Multiple apps (web, server, docs) | Multi-app handling, all modules enabled |
| `external-module` | Test external module | Module loading from flake input |

## Usage in CI

### Testing stack itself

```bash
# Using the test script (recommended)
./nix/flake/templates/_test-fixtures/run-tests.sh

# Run specific fixtures
./nix/flake/templates/_test-fixtures/run-tests.sh basic with-oxlint

# Manual: Run all fixture checks
for fixture in nix/flake/templates/_test-fixtures/*/; do
  echo "Testing $(basename $fixture)..."
  nix flake check "$fixture" --override-input stack path:. --no-write-lock-file
done
```

### Testing an external module

Fixtures are exposed as flake templates for easy access:

```bash
# Initialize a test fixture
nix flake init -t github:darkmatter/stack#test-external-module

# Override the module input with your module
nix flake lock --override-input test-module path:../my-module

# Run checks
nix flake check
```

### Available templates

| Template | Description |
|----------|-------------|
| `test-basic` | Minimal config, no apps |
| `test-with-oxlint` | OxLint module enabled |
| `test-full-stack` | All features (multiple apps, modules) |
| `test-external-module` | For testing external modules |

```bash
# List all available templates
nix flake show github:darkmatter/stack --json | jq '.templates | keys'
```

## Creating New Fixtures

1. Copy an existing fixture as a starting point
2. Modify `.stack/config.nix` for your scenario
3. Add any test apps in `apps/` if needed
4. Add test checks in `flake.nix` if needed

## Fixture Structure

```
fixture-name/
├── flake.nix                 # Flake with stack + test checks
├── flake.lock                # Optional: lock file for reproducibility
├── .stack/
│   └── config.nix            # Scenario configuration
└── apps/                     # Optional: test apps
    └── web/
        ├── src/
        │   └── index.ts
        └── package.json
```
