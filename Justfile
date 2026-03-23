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

# ------ Deployment -------

rootdir := `git rev-parse --show-toplevel`
secrets := rootdir / ".stack/secrets/vars/dev.sops.yaml"
is_aws_active := `aws sts get-caller-identity --query Arn --output text | grep -q 'aws' && echo true || echo false`
aws_vault := if is_aws_active == "true" {""} else { "aws-vault exec sso-prod --" }

# Deploy web app to EC2
deploy app='web' region='us-west-2':
    @if [ "{{app}}" != "web" ]; then echo "Only 'web' is supported for EC2 deploy"; exit 1; fi
    {{aws_vault}} bash "{{rootdir}}/scripts/deploy/deploy-web.sh" "{{region}}"

# Deploy via NixOS: nix build -> cachix push -> alchemy infra -> colmena apply
deploy-nixos app='web':
    bash "{{rootdir}}/scripts/deploy/deploy-nixos.sh" "{{app}}"

# Check deploy status
deploy-status app='web' region='us-west-2':
    @if [ "{{app}}" != "web" ]; then echo "Only 'web' is supported"; exit 1; fi
    {{aws_vault}} bun "{{rootdir}}/scripts/deploy/status.ts" "{{region}}"

# View deploy logs
deploy-logs app='web' region='us-west-2' lines='120':
    @if [ "{{app}}" != "web" ]; then echo "Only 'web' is supported"; exit 1; fi
    {{aws_vault}} bun "{{rootdir}}/scripts/deploy/logs.ts" "{{region}}" "{{lines}}"

# Build web artifact only (no deploy)
deploy-build-artifact region='us-west-2':
    bash "{{rootdir}}/scripts/deploy/build-artifact.sh" "{{region}}"

# Publish web artifact to S3 only (no deploy)
deploy-publish-artifact region='us-west-2':
    {{aws_vault}} bash "{{rootdir}}/scripts/deploy/publish-artifact.sh" "{{region}}"
