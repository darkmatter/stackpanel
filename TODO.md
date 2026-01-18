# Stackpanel TODOs

Centralized task list for the Stackpanel project.

______________________________________________________________________

## CLI (`apps/stackpanel-go/`)

### Completed

- [x] **Shell completion** - Cobra provides `completion` subcommand for zsh/bash/fish
- [x] **git-hooks.nix** - Exists in `nix/stackpanel/modules/git-hooks.nix`
- [x] **caddy** - Full module in `nix/stackpanel/services/caddy.nix` with commands
- [x] **step** - Full module in `nix/stackpanel/network/network.nix`
- [x] **auto infra (sst)** - Full SST module in `nix/stackpanel/sst/sst.nix`
- [x] **Go tests** - 18+ test files covering TUI, navigation, services, nix eval, docgen
- [x] **Services commands** - start, stop, status, restart, logs, list all implemented
- [x] **Auto docgen** - `stackpanel gendocs` generates MDX from Nix options and CLI commands
- [x] **Tasks** - `stackpanel.tasks` config with turbo.json generation and devenv-tasks integration

### High Priority

- [ ] in setup,the project directory shows "unknown" and the github repository shows "uncofnigured"
- [ ] the user-specific directory says .stackpanel but should be ~/.stackpanel
- [ ] AWS auto deployment should probably tell you to run `stackpanel run sst:deploy` once configured
- [ ] Create a healthchecks module - any module should be able to declare a "healthcheck" that can either be nix code or a script to check if that module is healthy. Each module that does this should have a traffic light in the UI, with a green light indicating that it is in a healthy state
- [ ] Do a pass on all generated files and make sure they are going through stackpanel.files - most of them currently dont show up in the UI because they are not there when evaluated
- [ ] services needs to be modular - there should be a serviceModule schema that services register to. There should be NO trace of the word "postgres" or "redis" or "minio" in the core stackpanel code
- [ ] **AWS hardening** - Additional AWS security features beyond cert-based auth



### Medium Priority

- [ ] **Interactive stop** - Add TUI for `stackpanel services stop`
- [ ] **Logs TUI** - Interactive log viewer with scrollback
- [ ] **Service health checks** - Periodically check service health

### Low Priority

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

### Devenv (`nix/stackpanel/`)

- [x] Create devenv wrapper module
- [x] Service presets (postgres, redis, minio, caddy) - *Done via global-services.nix*
- [x] Shell theming (starship presets)
- [x] VSCode integration (terminal profile, workspace, YAML schemas) - *Done via ide.nix*
- [x] Process-compose integration - *Done via modules/process-compose.nix*
- [ ] Language detection (auto-enable based on project files)
- [ ] Integrate secrets (auto-load decrypted secrets in devshell)

______________________________________________________________________

## Nix General (`nix/`)

- [x] Template for `nix flake init -t github:stack-panel/nix`
- [x] Devenv integration (devenvModules)
- [x] Non-flake compatibility (default.nix, shell.nix)
- [x] Standalone modules (no flake-parts dependency)
- [x] VSCode module - *Done via ide.nix with workspace generation, terminal integration, YAML schemas*
- [x] Multiple templates (default, devenv, minimal, native)
- [ ] Integration tests

______________________________________________________________________

## Agent (`apps/stackpanel-go/internal/agent/`)

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

## Documentation (`apps/docs/`)

- [x] Getting started guide - *Quick start at docs/quick-start.mdx*
- [x] CLI reference documentation - *Full CLI docs at docs/cli/*
- [x] Nix modules reference - *Reference docs at docs/reference/*
- [ ] Contributing guide

______________________________________________________________________

## Completed

- [x] Global singleton services architecture (`nix/stackpanel/core/`)
- [x] Devenv global services module (`nix/stackpanel/services/global-services.nix`)
- [x] Stackpanel CLI with Cobra (`apps/stackpanel-go/`)
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
- [x] SST infrastructure module for AWS provisioning
- [x] Git hooks integration
- [x] Process-compose orchestration
