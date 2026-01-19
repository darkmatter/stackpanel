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

______________________________________________________________________

## MOTD Improvements (`apps/stackpanel-go/internal/tui/motd.go`)

Improve the `stackpanel motd` command to be more helpful for new users.

### Layout

```
╭──────────────────────────────────────────────────────────────────────────╮
│  [ASCII Banner]                                                          │
│                                                                          │
│  MyProject Shell                                    v1.2.3               │
│  Your reproducible development environment is ready                      │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Status                                                                  │
│    Agent     ● localhost:9876           Studio → localhost:3000/studio   │
│    Services  ● postgres  ● redis  ○ minio                                │
│    AWS       ⚠ credentials expired      Health ████████░░ 8/10           │
│                                                                          │
│  Environment                                                             │
│    Node 20.11.0  •  Bun 1.1.8  •  Go 1.22  •  PostgreSQL 16              │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Quick Start                             Shortcuts                       │
│    dev             Start services          sp   = stackpanel             │
│    dev stop        Stop services           spx  = run devshell command   │
│    sp status       Full dashboard          x    = spx (configurable)     │
│                                                                          │
│  Your Commands (12 available)                                            │
│    db:migrate      Run database migrations                               │
│    db:seed         Seed development data                                 │
│    test            Run test suite                                        │
│    ...             Run `sp commands` for full list                       │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  ⚠ Action Required                                                       │
│    • Agent not running → stackpanel agent                                │
│    • AWS session expired → stackpanel aws login                          │
│    • 2 files stale → stackpanel files sync                               │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  💡 Update available: v1.3.0 (you have v1.2.3) → nix flake update        │
│                                                                          │
│  Resources                                                               │
│    Docs     https://stackpanel.dev/docs                                  │
│    Studio   http://localhost:3000/studio?project=myproject               │
╰──────────────────────────────────────────────────────────────────────────╯
```

### P0 - Must Have

- [x] **Agent status detection** - Check if localhost:9876/health responds, show fix instructions if not
- [x] **Studio link** - Show clickable link to `http://localhost:3000/studio?project={id}`
- [x] **Condensed commands list** - Show top 5 user commands with "run `sp commands` for full list"
- [x] **Alias documentation** - Explain `sp`, `spx`, and `x` shortcuts
- [x] **Docs link** - Show `https://stackpanel.dev/docs`

### P1 - Should Have

- [x] **AWS status with warnings** - Check `aws sts get-caller-identity`, show ⚠ if invalid
- [x] **Generated files summary** - Show "X stale / Y total" with fix command
- [x] **Action Required section** - Conditional section showing issues with fix commands
- [x] **Environment info** - Show enabled languages/tools (Node version, Go version, etc.)
- [x] **Health score** - Visual progress bar `████████░░ 8/10` from healthchecks

### P2 - Nice to Have

- [x] **Update notification** - Check for newer stackpanel version, show update command

### Implementation

#### Phase 1: Data Collection ✅

Created `apps/stackpanel-go/internal/tui/motd_data.go`:

```go
type MOTDData struct {
    // Project info
    ProjectName string
    Version     string
    
    // Status checks
    Agent       AgentStatus
    Services    []ServiceStatus
    AWS         AWSStatus
    Health      HealthSummary
    Files       FilesStatus
    Environment EnvironmentInfo
    
    // Commands
    DefaultCommands []MOTDCommand
    UserCommands    []MOTDCommand
    TotalCommands   int
    
    // Configuration
    ShortcutAlias   string
    StudioURL       string
    DocsURL         string
    AgentPort       int
    
    // Computed
    Issues          []Issue
    UpdateAvailable *UpdateInfo
}

func CheckAgentStatus(port int) AgentStatus
func CheckAWSStatus() AWSStatus
func CheckFilesStatus(projectRoot string) FilesStatus
func GetEnvironmentInfo() EnvironmentInfo
func GetUserCommands(projectRoot string) ([]MOTDCommand, int)
func CheckForUpdates(currentVersion string) *UpdateInfo
func CollectMOTDData(cfg *nixconfig.Config) *MOTDData
```

#### Phase 2: Update Rendering ✅

Modified `apps/stackpanel-go/internal/tui/motd.go`:
- Added `RenderImprovedMOTD()` function with all new sections
- Added new render functions for each section (status, environment, shortcuts, etc.)
- Added conditional rendering for Issues section
- Added health bar visualization
- Preserved legacy `RenderMOTD()` for backward compatibility

#### Phase 3: Update CLI Command ✅

Modified `apps/stackpanel-go/cmd/cli/motd.go`:
- Added `CollectMOTDData()` call to gather all info
- Added `--json` flag for machine-readable output
- Added `--force` flag to show MOTD even if disabled
- Added `--legacy` flag to use old MOTD format

### Files Modified ✅

| File | Status |
|------|--------|
| `apps/stackpanel-go/internal/tui/motd_data.go` | ✅ Created - Data collection functions |
| `apps/stackpanel-go/internal/tui/motd.go` | ✅ Updated - Added `RenderImprovedMOTD()` and new sections |
| `apps/stackpanel-go/cmd/cli/motd.go` | ✅ Updated - Added flags and improved orchestration |
