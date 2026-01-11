# Plan: Generated Files UI & Process-Compose Integration

## Overview

This document outlines the plan for:
1. A UI to view and manage generated files in stackpanel
2. Integration with process-compose for app running state

---

## Part 1: Generated Files UI

### Current State

Stackpanel has a Nix-based file generation system (`stackpanel.files`) that:
- Allows modules to declare files to generate via `stackpanel.files.entries`
- Supports two types: `text` (inline content) and `derivation` (from Nix derivation)
- Generates a `write-files` command that materializes files on shell entry
- Files are written to the project root based on their key path

**Current file contributors:**
- `nix/stackpanel/ide/ide.nix` - VS Code workspace, devshell loader
- `nix/stackpanel/modules/go.nix` - package.json, .air.toml for Go apps
- `nix/stackpanel/modules/bun.nix` - package.json for Bun apps
- `nix/stackpanel/modules/process-compose.nix` - (planned) process-compose.yml

**Problem:** There's no visibility into:
- What files are being generated
- Which module is generating each file
- What the file contents will be
- Whether files are up-to-date or need regeneration

### Proposed Solution

#### 1. New API Endpoint: `/api/nix/files`

Add an endpoint to the Go agent that returns the list of generated files.

```go
// GET /api/nix/files
type GeneratedFile struct {
    Path        string `json:"path"`        // Relative path (key in entries)
    Type        string `json:"type"`        // "text" or "derivation"
    Mode        string `json:"mode"`        // File permissions (e.g., "0755")
    Source      string `json:"source"`      // Module that contributed this file
    StorePath   string `json:"storePath"`   // Nix store path of content
    Size        int64  `json:"size"`        // File size in bytes
    Hash        string `json:"hash"`        // Content hash for change detection
    ExistsOnDisk bool  `json:"existsOnDisk"` // Whether file exists in workspace
    IsStale     bool   `json:"isStale"`     // Whether disk file differs from generated
}

type GeneratedFilesResponse struct {
    Files       []GeneratedFile `json:"files"`
    TotalCount  int             `json:"totalCount"`
    StaleCount  int             `json:"staleCount"`
    LastWritten string          `json:"lastWritten"` // ISO timestamp
}
```

**Implementation approach:**
1. Evaluate `config.stackpanel.files.entries` via nix eval
2. For each entry, resolve the store path and compute metadata
3. Compare with on-disk files to determine staleness

#### 2. Nix Schema Extension

Extend the files entry schema to include source tracking:

```nix
# In stackpanel.files.entries
"path/to/file" = {
  type = "text" | "derivation";
  text = "...";           # if type = "text"
  drv = <derivation>;     # if type = "derivation"
  mode = "0644";          # optional
  source = "go.nix";      # NEW: module that contributed this
  description = "...";    # NEW: human-readable description
};
```

#### 3. New Studio Panel: `/studio/files`

Create a new panel to display generated files.

**Features:**
- List all generated files with metadata
- Group by source module
- Show stale/up-to-date status
- Preview file contents
- Manual regeneration trigger
- Diff view for stale files

**UI Components:**

```
┌─────────────────────────────────────────────────────────────────┐
│ Generated Files                                    [Regenerate] │
├─────────────────────────────────────────────────────────────────┤
│ 12 files • 2 stale • Last written: 2 minutes ago                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ▼ IDE (3 files)                                                │
│   ├─ .vscode/stackpanel.code-workspace      ✓ up-to-date       │
│   ├─ .stackpanel/gen/devshell-loader.sh     ✓ up-to-date       │
│   └─ .stackpanel/gen/settings.json          ⚠ stale            │
│                                                                 │
│ ▼ Go Apps (4 files)                                            │
│   ├─ apps/stackpanel-go/package.json        ✓ up-to-date       │
│   ├─ apps/stackpanel-go/.air.toml           ✓ up-to-date       │
│   └─ ...                                                        │
│                                                                 │
│ ▼ Process Compose (1 file)                                     │
│   └─ .process-compose.yml                   ✓ up-to-date       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**File detail drawer:**
```
┌─────────────────────────────────────────────────────────────────┐
│ .process-compose.yml                               [Close]      │
├─────────────────────────────────────────────────────────────────┤
│ Source: process-compose.nix                                     │
│ Type: derivation                                                │
│ Mode: 0644                                                      │
│ Size: 1.2 KB                                                    │
│ Status: ✓ Up-to-date                                           │
├─────────────────────────────────────────────────────────────────┤
│ Preview:                                                        │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ version: "0.5"                                              │ │
│ │ processes:                                                  │ │
│ │   web:                                                      │ │
│ │     command: bun run dev                                    │ │
│ │     working_dir: apps/web                                   │ │
│ │   ...                                                       │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 2: Process-Compose Integration

### Current State

- Process-compose is available via `process-compose-flake` input
- Devenv has process-compose integration but we want to avoid devenv dependency
- `nix/stackpanel/modules/process-compose.nix` exists but generates devenv processes
- No standalone `.process-compose.yml` generation currently

### Proposed Solution

#### 1. Generate `.process-compose.yml` from App Config

Each app in `stackpanel.apps` should contribute a process definition.

**New Nix module: `nix/stackpanel/modules/process-compose-standalone.nix`**

```nix
# For each app with scripts.process-compose.enable = true:
# Generate a process entry in .process-compose.yml

{
  stackpanel.files.entries.".process-compose.yml" = {
    type = "derivation";
    source = "process-compose";
    description = "Process orchestration config for all apps";
    drv = pkgs.writeText "process-compose.yml" (lib.generators.toYAML {} {
      version = "0.5";
      processes = lib.mapAttrs (name: app: {
        command = app.devCommand or "npm run dev";
        working_dir = app.path;
        availability = {
          restart = "on_failure";
          backoff_seconds = 2;
          max_restarts = 5;
        };
      }) enabledApps;
    });
  };
}
```

**Example generated `.process-compose.yml`:**

```yaml
version: "0.5"

processes:
  web:
    command: bun run dev
    working_dir: apps/web
    availability:
      restart: on_failure
      backoff_seconds: 2
      max_restarts: 5
    environment:
      - PORT=3000
  
  server:
    command: bun run dev
    working_dir: apps/server
    availability:
      restart: on_failure
      backoff_seconds: 2
      max_restarts: 5
    depends_on:
      postgres:
        condition: process_healthy

  stackpanel-go:
    command: air
    working_dir: apps/stackpanel-go
    availability:
      restart: on_failure
```

#### 2. App Schema Extension

Extend `AppEntity` to include process-compose settings:

```typescript
interface AppEntity {
  // ... existing fields ...
  
  // Process-compose settings
  process?: {
    enable?: boolean;        // Include in process-compose (default: true)
    command?: string;        // Override dev command
    dependsOn?: string[];    // Other processes this depends on
    env?: Record<string, string>; // Additional env vars
    readyProbe?: {           // Health check
      httpGet?: { path: string; port: number };
      exec?: { command: string };
    };
  };
}
```

#### 3. Query Running State via Process-Compose API

Process-compose exposes a REST API (default port 8080) or Unix socket.

**New agent endpoint: `/api/processes`**

```go
// GET /api/processes
type ProcessStatus struct {
    Name       string `json:"name"`
    Status     string `json:"status"`     // "Running", "Stopped", "Failed", etc.
    PID        int    `json:"pid"`
    Uptime     string `json:"uptime"`
    Restarts   int    `json:"restarts"`
    ExitCode   *int   `json:"exitCode"`   // null if running
    IsRunning  bool   `json:"isRunning"`
}

type ProcessesResponse struct {
    Available bool            `json:"available"` // Is process-compose running?
    Processes []ProcessStatus `json:"processes"`
}
```

**Implementation:**
1. Check if `.process-compose.yml` exists
2. Try to connect to process-compose socket/API
3. If available, query `/processes` endpoint
4. Return status for each process

**Process-compose API reference:**
- `GET /processes` - List all processes
- `POST /process/{name}/start` - Start a process
- `POST /process/{name}/stop` - Stop a process
- `POST /process/{name}/restart` - Restart a process

#### 4. Apps Panel Integration

Update the apps panel to show running state:

```typescript
// In apps-panel-alt.tsx
const { data: processStatus } = useProcessStatus();

// For each app, look up its process status
const isRunning = processStatus?.processes?.find(
  p => p.name === app.id
)?.isRunning ?? false;
```

**UI changes:**
- Green dot = running
- Gray dot = stopped
- Red dot = failed/crashed
- Tooltip shows uptime/exit code
- Quick actions: Start/Stop/Restart buttons

---

## Implementation Order

### Phase 1: Generated Files Foundation
1. [ ] Extend Nix files schema with `source` and `description` fields
2. [ ] Add `/api/nix/files` endpoint to agent
3. [ ] Create basic `/studio/files` panel listing files

### Phase 2: Files UI Polish
4. [ ] Add file preview/content viewer
5. [ ] Add staleness detection and diff view
6. [ ] Add manual regeneration trigger
7. [ ] Add grouping by source module

### Phase 3: Process-Compose Generation
8. [ ] Create `process-compose-standalone.nix` module
9. [ ] Extend app schema with process settings
10. [ ] Generate `.process-compose.yml` via `stackpanel.files`

### Phase 4: Process Status Integration
11. [ ] Add `/api/processes` endpoint to agent
12. [ ] Create `useProcessStatus` hook
13. [ ] Update apps panel with running indicators
14. [ ] Add start/stop/restart actions

---

## Open Questions

1. **Socket vs TCP for process-compose?**
   - Unix socket is default in devenv (`$XDG_RUNTIME_DIR/devenv-*/pc.sock`)
   - TCP (port 8080) is more portable
   - Recommendation: Support both, prefer socket if available

2. **Where should `.process-compose.yml` live?**
   - Option A: Project root (standard location)
   - Option B: `.stackpanel/gen/process-compose.yml` (grouped with other generated files)
   - Recommendation: Project root for better tooling compatibility

3. **How to handle apps without dev commands?**
   - Some apps (libraries, packages) don't have a dev server
   - Should auto-detect based on `type` or explicit `process.enable = false`

4. **Should we support custom process-compose processes?**
   - e.g., database services, queue workers
   - Could extend beyond just apps
   - Consider `stackpanel.processes` separate from `stackpanel.apps`

---

## File Structure After Implementation

```
apps/web/src/
├── routes/studio/
│   └── files.tsx                    # New route
├── components/studio/panels/
│   ├── files/
│   │   ├── files-panel.tsx          # Main panel
│   │   ├── file-preview.tsx         # Content viewer
│   │   └── file-diff.tsx            # Diff viewer
│   └── apps-panel-alt.tsx           # Updated with process status
├── lib/
│   ├── use-generated-files.ts       # Hook for files API
│   └── use-process-status.ts        # Hook for process API

apps/stackpanel-go/internal/agent/server/
├── files.go                         # /api/nix/files handler
└── processes.go                     # /api/processes handler

nix/stackpanel/
├── modules/
│   └── process-compose-standalone.nix  # New module
└── devshell/
    └── files.nix                    # Extended with source tracking
```
