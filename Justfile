# Stackpanel Development Commands
# Install just: https://github.com/casey/just

# Default recipe - show help
default:
    @just --list

# Run all tests
test:
    @echo "Running all tests..."
    ./tests/smoke-test.sh --both
    ./tests/test-templates.sh

# Run smoke tests only
test-smoke:
    ./tests/smoke-test.sh --both

# Test devenv shell only
test-devenv:
    ./tests/smoke-test.sh --devenv

# Test native shell only
test-native:
    ./tests/smoke-test.sh --native

# Test all templates
test-templates:
    ./tests/test-templates.sh

# Test specific template
test-template name:
    ./tests/test-templates.sh --template {{name}}

# Run nix flake check
check:
    nix flake check --impure

# Quick validation (fast checks only)
validate:
    @echo "Running quick validation..."
    nix flake check --impure

# Build and enter devenv shell
dev:
    nix develop --impure

# Build and enter native shell
dev-native:
    SKIP_DEVENV=true nix develop --impure

# Clean nix-direnv cache
clean-cache:
    rm -rf ~/.cache/nix-direnv
    direnv reload

# Show available packages in shell
show-packages:
    nix shell .#devShells.aarch64-darwin.default --impure --command bash -c 'echo $PATH | tr ":" "\n" | grep /nix/store'
