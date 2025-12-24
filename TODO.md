# Stackpanel TODOs

Centralized task list for the Stackpanel project.

______________________________________________________________________

## CLI (`apps/cli/`)

### High Priority

- [ ] **Shell completion** - Add zsh/bash completion setup to the devenv
  - Generate completions with `stackpanel completion zsh > ...`
  - Auto-source in devenv enterShell
- [ ] **Database subcommand** - Add `stackpanel db` for database operations
  - `stackpanel db list` - List all databases
  - `stackpanel db create <name>` - Create database
  - `stackpanel db drop <name>` - Drop database
  - `stackpanel db migrate` - Run migrations
  - `stackpanel db seed` - Seed data

### Medium Priority

- [ ] **Go tests** - Add comprehensive tests for CLI commands
  - Unit tests for TUI models
  - Integration tests for service management
  - Currently only `gendocs_test.go` exists
- [ ] **Interactive stop** - Add TUI for `stackpanel services stop`
- [ ] **Logs TUI** - Interactive log viewer with scrollback
- [ ] **Service health checks** - Periodically check service health

### Low Priority

- [ ] **Config file** - Support `~/.config/stackpanel/config.yaml`
- [ ] **Plugin system** - Allow custom service definitions

______________________________________________________________________

## Nix Modules (`nix/modules/`)

### Core

- [ ] Add `nix run .#generate-clean` to remove managed files
- [ ] Add file checksums to detect manual edits
- [ ] Support merge strategies (append vs overwrite)

### AWS (`aws.nix`)

- [x] Cert-based auth (AWS Roles Anywhere) - *Working*
- [ ] Basic IAM role/policy generation
- [ ] S3 bucket configuration
- [ ] Lambda function deployment
- [ ] Secrets Manager sync with agenix
- [ ] VPC configuration
- [ ] RDS/Aurora setup
- [ ] CloudFront CDN
- [ ] Route53 DNS

### Secrets (`secrets/`)

- [ ] Auto-sync users from GitHub
- [ ] GitHub Action to re-key automatically
- [ ] Auto-generate KMS key, add as SOPS recipient (enables AWS SOPS Auth)

### Container

- [ ] Create container module (currently does not exist)
- [ ] nix2container generation
- [ ] Auto-detect project type (Node, Go, Python, etc.)
- [ ] Generate optimized Dockerfile per stack
- [ ] Docker compose generation
- [ ] Registry authentication
- [ ] Nix-based images (dockerTools)
- [ ] Health checks
- [ ] Security scanning integration

### CI (`ci.nix`)

- [x] GitHub Actions workflow generation - *Working*
- [ ] Add `deploy` high-level option (CD)
- [ ] Add `release` workflow (semantic release, changelogs)
- [ ] Support GitLab CI
- [ ] Support other CI systems (CircleCI, etc.)
- [ ] Add matrix builds option
- [ ] Add caching configuration
- [ ] Use github API to add support for uploading secrets to Github Actions
  - [ ] Give github an age key, then all other secrets can be checked in and even decrypted by github using SOPS
  - [ ] Explore OIDC so not even that first key is needed, and let it auth against internal auth server. Possible that the role for github to use wont even have to be specified if we add autocreation of trust policy based on the github repo, so if OIDC identity is <org>/<repo> and that matches the current <org>/<repo> then it can allow permission.

### Network (`network.nix`)

- [x] Step-CA certificate management - *Working*
- [ ] Tailscale auth key management
- [ ] DNS server setup (CoreDNS or Caddy)
- [ ] Auto-register services in DNS
- [ ] mTLS between services

### Devenv (`devenv/`)

- [x] Create devenv wrapper module
- [x] Service presets (postgres, redis, minio, caddy) - *Done via global-services.nix*
- [x] Shell theming (starship presets)
- [x] VSCode integration (terminal profile, workspace, YAML schemas) - *Done via ide.nix*
- [ ] Language detection (auto-enable based on project files)
- [ ] Integrate secrets (auto-load decrypted secrets in devshell)

______________________________________________________________________

## Nix General (`nix/`)

- [x] Template for `nix flake init -t github:stack-panel/nix`
- [x] Devenv integration (devenvModules)
- [x] Non-flake compatibility (default.nix, shell.nix)
- [x] Standalone modules (no flake-parts dependency)
- [x] VSCode module - *Done via ide.nix with workspace generation, terminal integration, YAML schemas*
- [ ] Integration tests

______________________________________________________________________

## Agent (`apps/agent/`)

- [ ] Implement proper authentication (currently localhost-only)
- [ ] WebSocket connection improvements
- [ ] API documentation

______________________________________________________________________

## Web App (`apps/web/`)

- [ ] Add React Native components to `ui-native`

______________________________________________________________________

## Infrastructure (`infra/`)

- [ ] Set up Gatus monitoring in production

______________________________________________________________________

## Documentation

- [ ] Getting started guide
- [ ] CLI reference documentation
- [ ] Nix modules reference
- [ ] Contributing guide

______________________________________________________________________

## Completed

- [x] Global singleton services architecture (`nix/lib/core/global-services.nix`)
- [x] Devenv global services module (`nix/modules/global-services.nix`)
- [x] Stackpanel CLI with Cobra (`apps/cli/`)
- [x] Bubble Tea TUI integration
- [x] Interactive status dashboard
- [x] Service start with progress indicators
- [x] VSCode IDE integration with workspace generation
- [x] YAML schema generation for secrets config
- [x] Ports module with deterministic port assignment
- [x] Caddy reverse proxy integration
- [x] AWS Roles Anywhere cert-based auth
- [x] Step-CA certificate management
- [x] Starship prompt theming
- [x] GitHub Actions CI workflow generation
