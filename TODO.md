# Stackpanel TODOs

Centralized task list for the Stackpanel project.

______________________________________________________________________

## CLI (`cli/`)

### High Priority

- [ ] **Shell completion** - Add zsh/bash completion setup to the devenv
  - Generate completions with `stackpanel completion zsh > ...`
  - Auto-source in devenv enterShell
- [ ] **Cleanup old scripts** - Remove legacy shell scripts replaced by CLI
  - `dev-start`, `pg-start`, `redis-start`, etc. in devenv
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
- [ ] **Interactive stop** - Add TUI for `stackpanel services stop`
- [ ] **Logs TUI** - Interactive log viewer with scrollback
- [ ] **Service health checks** - Periodically check service health

### Low Priority

- [ ] **Config file** - Support `~/.config/stackpanel/config.yaml`
- [ ] **Plugin system** - Allow custom service definitions

______________________________________________________________________

## Nix Modules (`nix/modules/`)

### Core (`core/`)

- [ ] Consolidate options.nix into generate.nix (or vice versa)
- [ ] Add `nix run .#generate-clean` to remove managed files
- [ ] Add file checksums to detect manual edits
- [ ] Support merge strategies (append vs overwrite)

### AWS (`aws/`)

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

### Container (`container/`)

- [ ] nix2container generation
- [ ] Auto-detect project type (Node, Go, Python, etc.)
- [ ] Generate optimized Dockerfile per stack
- [ ] Docker compose generation
- [ ] Registry authentication
- [ ] Nix-based images (dockerTools)
- [ ] Health checks
- [ ] Security scanning integration

### CI (`ci/`)

- [ ] Add `deploy` high-level option (CD)
- [ ] Add `release` workflow (semantic release, changelogs)
- [ ] Support GitLab CI
- [ ] Support other CI systems (CircleCI, etc.)
- [ ] Add matrix builds option
- [ ] Add caching configuration

### Network (`network/`)

- [ ] Tailscale auth key management
- [ ] DNS server setup (CoreDNS or Caddy)
- [ ] Step-CA for internal certificates
- [ ] Auto-register services in DNS
- [ ] mTLS between services

### Devenv (`devenv/`)

- [x] Create devenv wrapper module
- [ ] Language detection (auto-enable based on project files)
- [x] Service presets (postgres, redis, etc.) - *Done via global-services.nix*
- [ ] Integrate secrets (auto-load decrypted secrets in devshell)
- [ ] VSCode integration (terminal profile, settings)
- [x] Shell theming (starship presets)

______________________________________________________________________

## Nix General (`nix/`)

- [x] Template for `nix flake init -t github:stack-panel/nix`
- [x] Devenv integration (devenvModules)
- [x] Non-flake compatibility (default.nix, shell.nix)
- [x] Standalone modules (no flake-parts dependency)
- [ ] Integration tests
- [ ] VSCode module

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

- [x] Global singleton services architecture (`nix/lib/services.nix`)
- [x] Devenv global services module (`nix/modules/devenv/global-services.nix`)
- [x] Stackpanel CLI with Cobra (`cli/`)
- [x] Bubble Tea TUI integration
- [x] Interactive status dashboard
- [x] Service start with progress indicators
