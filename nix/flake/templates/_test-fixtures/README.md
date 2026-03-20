# Test Fixtures

These fixtures are used for testing stackpanel modules in CI. They are **not** meant for `nix flake init`.

## Notes

- Fixtures use SSH URLs (`git+ssh://git@github.com/darkmatter/stackpanel`) which require SSH access to the repo
- Initial runs are slow due to fetching nixpkgs, flake-parts, etc. Subsequent runs use cached inputs
- Use `--no-write-lock-file` to avoid modifying the fixture's lock file
- Override `stackpanel` input with local path for development: `--override-input stackpanel path:.`

## Scenarios

| Fixture | Description | Tests |
|---------|-------------|-------|
| `basic` | Minimal config, no apps | Core evaluation, basic options |
| `with-oxlint` | OxLint enabled with web app | Linting module, file generation, scripts |
| `full-stack` | Multiple apps (web, server, docs) | Multi-app handling, all modules enabled |
| `external-module` | Test external module | Module loading from flake input |

## Snapshot Testing (Golden Files)

Each fixture can include a `golden/` directory containing the expected generated file contents.
When present, `nix flake check` will build the full file generation pipeline and `diff -r` the
output against `golden/`, failing if anything has changed.

This gives you end-to-end regression testing of the entire config → module evaluation → file
generation pipeline with reviewable diffs in PRs.

### How it works

```
.stack/config.nix                (input: scenario configuration)
    ↓ full NixOS module evaluation
stackpanelFullConfig.files       (evaluated file entries)
    ↓ _storePathsByFile
snapshot derivation              (all file contents assembled into a directory)
    ↓ diff -ru
golden/                          (checked-in expected output)
```

### Generating golden files for the first time

```bash
# Generate golden/ for all fixtures
./nix/flake/templates/_test-fixtures/update-golden.sh

# Generate golden/ for specific fixtures
./nix/flake/templates/_test-fixtures/update-golden.sh basic with-oxlint
```

### Updating golden files after a change

When you intentionally change what files a module generates (new file, changed content, etc.),
the snapshot check will fail with a unified diff showing exactly what changed. To accept the
new output:

```bash
# Update the fixture(s) that changed
./nix/flake/templates/_test-fixtures/update-golden.sh with-oxlint

# Review and commit
git diff nix/flake/templates/_test-fixtures/with-oxlint/golden/
git add nix/flake/templates/_test-fixtures/with-oxlint/golden/
```

### Inspecting the snapshot without updating

```bash
# Build the snapshot derivation and browse its contents
nix build ./nix/flake/templates/_test-fixtures/with-oxlint#snapshot \
  --override-input stackpanel path:. --no-write-lock-file
ls -la result/
```

## Usage in CI

### Testing stackpanel itself

```bash
# Using the test script (recommended)
./nix/flake/templates/_test-fixtures/run-tests.sh

# Run specific fixtures
./nix/flake/templates/_test-fixtures/run-tests.sh basic with-oxlint

# Manual: Run all fixture checks
for fixture in nix/flake/templates/_test-fixtures/*/; do
  echo "Testing $(basename $fixture)..."
  nix flake check "$fixture" --override-input stackpanel path:. --no-write-lock-file
done
```

### Testing an external module

Fixtures are exposed as flake templates for easy access:

```bash
# Initialize a test fixture
nix flake init -t github:darkmatter/stackpanel#test-external-module

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
nix flake show github:darkmatter/stackpanel --json | jq '.templates | keys'
```

## Creating New Fixtures

1. Copy an existing fixture as a starting point
2. Modify `.stack/config.nix` for your scenario
3. Add any test apps in `apps/` if needed
4. Add test checks in `flake.nix` if needed
5. Run `./update-golden.sh <fixture-name>` to generate the `golden/` directory
6. Commit the `golden/` directory — future `nix flake check` runs will validate against it

## Fixture Structure

```
fixture-name/
├── flake.nix                 # Flake with stackpanel + test checks
├── flake.lock                # Optional: lock file for reproducibility
├── .stack/
│   └── config.nix            # Scenario configuration
├── golden/                   # Snapshot: expected generated file contents
│   ├── .gitignore
│   └── ...
└── apps/                     # Optional: test apps
    └── web/
        ├── src/
        │   └── index.ts
        └── package.json
```
