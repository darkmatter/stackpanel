# Project Registration Points

This document describes all the points at which Stackpanel projects are automatically registered in the user configuration file at `~/.config/stackpanel/stackpanel.yaml`.

## Overview

When a project is "registered", it's added to the `projects` list in the user config. This allows:
- The agent to serve multiple projects from anywhere
- The web UI to switch between projects
- Quick access via project ID or name in API requests

## Registration Points

### 1. Running `stackpanel agent` from a Project Directory

**Trigger:** Starting the agent without a `-p` flag from within a project directory.

**Location:** `internal/agent/server/server.go` → `AutoRegister()`

```bash
cd ~/projects/my-app
stackpanel agent
# → Project auto-detected and registered
```

### 2. Running `stackpanel agent -p <path>`

**Trigger:** Starting the agent with an explicit project path.

**Location:** `internal/agent/server/server.go` → `OpenProject()`

```bash
stackpanel agent -p ~/projects/my-app
# → Project registered from the provided path
```

### 3. CLI Command: `stackpanel project add`

**Trigger:** Explicitly adding a project via CLI (with confirmation prompt).

**Location:** `cmd/cli/project.go` → `projectAddCmd`

```bash
stackpanel project add ~/projects/my-app
# → Shows project details and prompts: "Add this project? [y/N]"

# Skip confirmation with -y flag:
stackpanel project add -y ~/projects/my-app

# Add current directory:
stackpanel project add
```

### 4. CLI Command: `stackpanel project default`

**Trigger:** Setting a default project (adds if not already registered).

**Location:** `cmd/cli/project.go` → `projectDefaultCmd`

```bash
stackpanel project default ~/projects/my-app
# → Adds project if not already in list, then sets as default
```

### 5. API Endpoint: `POST /api/project/open`

**Trigger:** Opening a project via the web UI or API.

**Location:** `internal/agent/server/project_handlers.go` → `handleProjectOpen()`

```bash
curl -X POST -H "X-Stackpanel-Token: $TOKEN" \
  -d '{"path": "/path/to/project"}' \
  http://localhost:9876/api/project/open
```

### 6. CLI Command: `stackpanel init`

**Trigger:** Nix calls `stackpanel init` during shell entry.

**Location:** `cmd/cli/init.go` → `runInit()`

This is typically called automatically by the Nix devshell:
```nix
# In flake.nix or devenv.nix
shellHook = ''
  stackpanel init --config '${builtins.toJSON config}'
'';
```

### 7. CLI Command: `stackpanel scaffold`

**Trigger:** Scaffolding a new project.

**Location:** `cmd/cli/scaffold.go` → `runScaffold()`

```bash
cd ~/projects/new-app
stackpanel scaffold
# → Creates .stackpanel/ structure AND registers project
```

### 8. Any CLI Command from Project Directory (Auto-Detection) - OPT-IN

**Trigger:** Running any CLI command from within a project directory, when `STACKPANEL_AUTO_REGISTER=1` is set.

**Location:** `cmd/cli/root.go` → `PersistentPreRun` hook → `autoRegisterCurrentProject()`

```bash
# Enable auto-registration (opt-in)
export STACKPANEL_AUTO_REGISTER=1

cd ~/projects/my-app
stackpanel status
# → Project auto-detected and registered (if not already known)
```

**Note:** This is disabled by default because automatic registration can be surprising. Projects are still registered automatically by the other methods listed above (agent, init, scaffold, project add).

**Excluded commands** (they handle registration themselves or don't need it):
- `help`, `version`
- `dev` (dev mode commands)
- `project` (project management commands)
- `agent` (handles its own registration)
- `init`, `scaffold` (handle their own registration)

## Project Detection Logic

A directory is considered a Stackpanel project if it contains:

1. `.stackpanel/config.nix` - Primary indicator
2. `flake.nix` + `.git/` - Secondary indicator (git repo with Nix flake)

Detection walks up the directory tree from the current working directory until it finds a project root or reaches the filesystem root.

## Config File Structure

```yaml
# ~/.config/stackpanel/stackpanel.yaml
current_project: /Users/you/projects/my-app
default_project: /Users/you/projects/my-app
projects:
  - id: a1b2c3d4
    path: /Users/you/projects/my-app
    name: my-app
    last_opened: 2024-01-15T10:30:00-08:00
  - id: e5f6g7h8
    path: /Users/you/projects/other-app
    name: other-app
    last_opened: 2024-01-14T15:45:00-08:00
version: 1
```

## Project IDs

Each project gets a unique 8-character ID derived from the SHA256 hash of its absolute path. This ID is:
- Stable (same path always produces same ID)
- Short enough to type/remember
- Usable in API requests via `X-Stackpanel-Project` header

## Viewing Registered Projects

```bash
# List all registered projects
stackpanel project list

# Show details for a specific project
stackpanel project info my-app

# Show the config file location
cat ~/.config/stackpanel/stackpanel.yaml
```

## Removing Projects

```bash
# Remove by ID, name, or path
stackpanel project remove my-app

# This only removes from the config, doesn't delete any files
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `STACKPANEL_AUTO_REGISTER=1` | Enable automatic project registration when running CLI commands from a project directory |
| `STACKPANEL_USER_CONFIG` | Override the config file location (default: `~/.config/stackpanel/stackpanel.yaml`) |

## Confirmation Prompts

The `stackpanel project add` command shows a confirmation prompt before adding a project:

```
Project to add:

  Name: my-app
  ID:   a1b2c3d4
  Path: /Users/you/projects/my-app

Add this project? [y/N]
```

Use `-y` or `--yes` to skip the confirmation:

```bash
stackpanel project add -y ~/projects/my-app
```

## Project Validation

When adding a project, Stackpanel performs validation to ensure it's a legitimate project. This prevents accidentally registering system directories or non-project paths.

### What Gets Validated

| Check | Description |
|-------|-------------|
| **Path Safety** | Rejects system directories (`/tmp`, `/etc`, `/nix/store`, etc.) and the home directory itself |
| **Directory Exists** | Path must exist and be a directory |
| **Git Repository** | Must have a `.git` directory |
| **Stackpanel Markers** | Must have `.stackpanel/config.nix` OR a flake with stackpanel (see below) |
| **Config Content** | If `.stackpanel/config.nix` exists, checks for `enable` and `name` fields |

### Flake Detection (Nix-based)

For projects with `flake.nix` but no `.stackpanel/config.nix`, validation uses multiple detection methods in order of accuracy:

| Method | Description | Speed |
|--------|-------------|-------|
| **1. stackpanelConfig output** | Checks multiple flake output paths (see below) | ~2-5s |
| **2. Flake metadata** | Runs `nix flake metadata --json` and checks if any input contains "stackpanel" | ~1-3s |
| **3. Text search** | Falls back to searching `flake.nix` for "stackpanel" string patterns | Instant |

The nix-based checks can be skipped for faster validation using `ValidateProjectFast()` or `--skip-nix-eval` (when available).

### Validation Levels

| Level | Description |
|-------|-------------|
| **Strict** | Requires `.stackpanel/config.nix` with valid content |
| **Normal** | Accepts `.stackpanel/config.nix` OR flake with stackpanel (uses nix eval) |
| **Lenient** | Accepts any `flake.nix` (used for detection, not registration) |

### Validation Options

| Option | Description |
|--------|-------------|
| `SkipNixEval` | Skip nix-based checks for faster validation (less accurate for flake-only projects) |
| `NixTimeout` | Timeout for nix commands (default: 10s) |

### Project Types

After validation, projects are categorized:

| Type | Description | Detection Method |
|------|-------------|------------------|
| `stackpanel-config` | Has `.stackpanel/config.nix` (recommended) | File exists |
| `stackpanel-flake` | Has `flake.nix` with stackpanel | Nix eval or metadata |
| `flake-only` | Has `flake.nix` but no stackpanel (lenient only) | Text search fallback |

### Suspicious Paths

The following paths are automatically rejected:

- Root directory (`/`)
- Home directory itself (`~` but not `~/projects`)
- System directories: `/bin`, `/sbin`, `/usr`, `/etc`, `/var`, `/tmp`
- macOS system: `/System`, `/Library`, `/Applications`
- Nix store: `/nix/store`
- Homebrew cellar: `/opt/homebrew/Cellar`

### Validation Errors

| Error | Meaning |
|-------|---------|
| `not_found` | Directory doesn't exist |
| `not_git_repo` | No `.git` directory found |
| `not_stackpanel` | No `.stackpanel/config.nix` or `flake.nix` |
| `suspicious_path` | Path appears to be a system directory |
| `flake_not_stackpanel` | Has `flake.nix` but no stackpanel input/output detected |
| `invalid_config` | `.stackpanel/config.nix` is empty or malformed |

### How Flake Detection Works

1. **Check for `stackpanelConfig` output at multiple paths:**
   
   The following paths are checked in order (using the detected system, e.g., `aarch64-darwin`):
   ```bash
   # Top-level (stackpanel repo itself)
   nix eval .#stackpanelConfig.name --json --no-eval-cache
   
   # devShells passthru (user projects via devenv/devshell)
   nix eval .#devShells.<system>.default.passthru.stackpanelConfig.name --json --no-eval-cache
   
   # legacyPackages (alternative exposure method)
   nix eval .#legacyPackages.<system>.stackpanelConfig.name --json --no-eval-cache
   ```
   If any of these succeeds, the flake definitely uses stackpanel.

2. **Check flake inputs via metadata:**
   ```bash
   nix flake metadata --json .
   ```
   Parses the JSON and looks for any input node with "stackpanel" in the name or repo.

3. **Text search fallback:**
   Scans `flake.nix` for patterns like `stackpanel`, `stackpanelConfig`, `stackpanelModules`.

### Flake Output Locations

| Location | Used By |
|----------|---------|
| `.#stackpanelConfig` | Stackpanel repo itself |
| `.#devShells.<system>.default.passthru.stackpanelConfig` | User projects using devenv/devshell |
| `.#legacyPackages.<system>.stackpanelConfig` | User projects exposing via legacyPackages |

The system is auto-detected (e.g., `x86_64-linux`, `aarch64-darwin`) using `builtins.currentSystem` or Go runtime detection as fallback.

### Example Validation Output

```bash
$ stackpanel project add /tmp
✗ Invalid project: path appears to be a system or temporary directory

⚠ Validation details:
  • Path appears to be a system or temporary directory

$ stackpanel project add ~/random-repo
✗ Invalid project: flake.nix exists but doesn't appear to be a Stackpanel project

⚠ Validation details:
  • flake.nix exists but doesn't appear to be a Stackpanel project

$ stackpanel project add ~/my-stackpanel-project
Project to add:

  Name: my-stackpanel-project
  ID:   a1b2c3d4
  Path: /Users/you/my-stackpanel-project
  Type: stackpanel-config

Add this project? [y/N]
```
