# `internal/agent` — Stack Agent

The agent is a local HTTP server that bridges the web UI to the user's Nix
project on disk. It runs on `localhost:9876`, speaks JSON over REST (plus
Connect-RPC for typed endpoints), and pushes real-time updates via SSE.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  apps/web  (React UI)                                       │
│    → AgentHttpClient / Connect-RPC client                   │
└──────────────┬──────────────────────────────────────────────┘
               │  HTTP / SSE / WebSocket
┌──────────────▼──────────────────────────────────────────────┐
│  internal/agent/server   (HTTP handlers, middleware, SSE)    │
│    → delegates core data ops to pkg/nixdata                 │
│    → adds server-specific concerns: FlakeWatcher, caching,  │
│      SSE broadcast, evaluated entity merging                │
└──────────────┬──────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────┐
│  pkg/nixdata   (shared library — no net/http dependency)    │
│    → Store: read / write / patch / key-level updates        │
│    → Paths: filesystem layout resolution                    │
│    → Entities: validation, classification, map field names   │
│    → Transforms: kebab↔camel JSON key conversion            │
└──────────────┬──────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────┐
│  pkg/nix      (Nix serializer: Go values → Nix expressions) │
│  pkg/exec     (command executor with devshell support)       │
└─────────────────────────────────────────────────────────────┘
```

The core Nix data operations live in **`pkg/nixdata`** so both the agent
server and the CLI can share the same read/write/patch logic without
pulling in HTTP dependencies. The server package adds transport (HTTP
handlers, SSE events, FlakeWatcher caching) on top.

## Package Layout

```
internal/agent/
├── config/        # Agent configuration (env vars, defaults)
├── project/       # Project discovery, validation, multi-project management
└── server/        # HTTP server, route handlers, and supporting subsystems

pkg/nixdata/       # Shared Nix data library (used by both server and CLI)
├── store.go       # Store type: read, write, patch, key-level updates
├── paths.go       # Filesystem path resolution, config.nix constants
├── entities.go    # Entity validation and classification
└── transform.go   # JSON key transforms (kebab↔camel)
```

---

## `pkg/nixdata` — Shared Nix Data Library

This is the transport-agnostic foundation for all Nix data operations.
Both the agent HTTP server and the CLI construct a `Store` the same way:

```go
import (
    executor "github.com/darkmatter/stack/stack-go/pkg/exec"
    "github.com/darkmatter/stack/stack-go/pkg/nixdata"
)

exec, _ := executor.New(projectRoot, nil)
store := nixdata.NewStore(projectRoot, exec)

// Read an entity
data, err := store.ReadEntity("apps")

// Write an entity
path, err := store.WriteEntity("apps", myData)

// Key-level update (only touches one key in a map entity)
path, err := store.SetKey("variables", "/apps/web/port", portData)

// Patch a nested value in config.nix
err := store.PatchConsolidatedData("deployment.fly.organization", "my-org")
```

### Files

| File | Purpose |
|------|---------|
| `store.go` | `Store` struct and all read/write/patch methods. Accepts a `NixRunner` interface (satisfied by `*exec.Executor`). `ReadEntity`, `ReadEntityJSON`, `WriteEntity`, `WriteEntityJSON`, `SetKey`, `DeleteKey`, `ReadConsolidatedData`, `WriteConsolidatedData`, `PatchConsolidatedData`, `DeleteEntity`. |
| `paths.go` | `Paths` struct for filesystem layout resolution. Handles legacy per-entity files (`.stack/data/<entity>.nix`) vs consolidated (`.stack/config.nix`). Also holds `ConfigNixHeader`, `SectionHeaders()`, and `ParseConfigPath()`. |
| `entities.go` | Pure functions: `ValidateEntityName`, `IsExternalEntity`, `IsMapEntity`, `IsEvaluatedEntity`, `MapFieldNames`. |
| `transform.go` | JSON key transforms: `KebabToCamel`, `CamelToKebab`, `TransformKeysToCamel`, `TransformKeysToKebab`, `NixJSONToCamelCase`, `CamelCaseToNixJSON`. Map-field-aware — user-defined keys (variable IDs, app names, etc.) are preserved verbatim. |

### NixRunner Interface

The `Store` needs to evaluate Nix expressions. Instead of depending on
`*exec.Executor` directly, it accepts a `NixRunner` interface:

```go
type NixRunner interface {
    RunNix(args ...string) (*executor.Result, error)
}
```

`*exec.Executor` satisfies this out of the box. For tests, any struct with
a matching `RunNix` method works.

---

## `internal/agent/config`

| File | Purpose |
|------|---------|
| `config.go` | `Config` struct and `Load()`. All config comes from env vars (no config file). Key fields: `ProjectRoot`, `Port`, `BindAddress`, `DataDir` (`~/.stack`). |

## `internal/agent/project`

| File | Purpose |
|------|---------|
| `project.go` | `Manager` for multi-project support: open, close, list, auto-detect. `ValidateProject*()` functions check that a directory is a real Stack project (git repo, flake with stack output, etc). |

## `internal/agent/server`

This is the HTTP layer. Files are grouped by domain below.

---

### Core Server

| File | Purpose |
|------|---------|
| `server.go` | `Server` struct, `New()` constructor (registers **all** routes), `Start()` / `Stop()`. The route table in `New()` is the single index of every endpoint — start here when looking for a handler. The `Server` holds a `*nixdata.Store` field that all data handlers delegate to. |
| `embed.go` | `//go:embed` for the `templates/` directory (pairing HTML page). |

### Middleware & Auth

| File | Purpose |
|------|---------|
| `cors_auth.go` | `withCORS()`, `withLogging()`, `requireAuth()` middleware. Origin allow-list logic, token extraction from `Authorization` header. |
| `jwt.go` | `JWTManager` — generates and validates agent JWT tokens. Tokens are created during pairing and last 30 days. |
| `pair.go` | `GET /pair` — serves the browser pairing page. The page receives a one-time token via `postMessage` so the web UI can authenticate future requests. |
| `project_context.go` | Context key helpers for attaching the resolved `Project` to a request context. |

### Nix Data (HTTP Handlers)

These handlers sit on top of `pkg/nixdata`. They add HTTP request/response
handling, FlakeWatcher integration, and evaluated-entity merging.

| File | Purpose |
|------|---------|
| `nix_data.go` | **Main data handler.** HTTP endpoints for `/api/nix/data` (GET/POST/DELETE) and `/api/nix/data/list`. Delegates to `s.store` (`*nixdata.Store`) for all filesystem operations. Also provides thin wrapper methods (`readNixEntityJSON`, `writeNixEntityJSON`, `readConsolidatedData`, `writeConsolidatedData`, `patchConsolidatedData`) so that Connect handlers and other server files compile unchanged. Server-specific logic (FlakeWatcher lookup, evaluated entity merging) stays here. |
| `nix_config.go` | `GET/POST /api/nix/config` — returns the fully-evaluated flake config (`stackpanelConfig`). Caches aggressively; POST forces a re-eval. |
| `nix_files.go` | `GET /api/nix/files` — lists generated files declared in the Nix config, enriched with on-disk status (`existsOnDisk`, `isStale`). |
| `nix_ui.go` | `GET /api/nix/ui/runtime` and `/api/nix/ui/extensions` — lightweight JSON snapshots of the runtime config and extension metadata for the UI. Cached with short TTL. |
| `json_transform.go` | Thin wrappers over `pkg/nixdata` transform functions. Exists so older server code continues to compile; new code should use `nixdata.*` directly. |

#### Data Write Flow (UI → disk)

```
UI component
  → AgentHttpClient.post("/api/nix/data", { entity, data, key? })

    server/nix_data.go: handleNixDataWrite()
      ├─ key set? → store.SetKey() or store.DeleteKey()   [pkg/nixdata]
      └─ no key   → store.WriteEntity()                   [pkg/nixdata]
                       → nixser.SerializeIndented()        [pkg/nix]
                         → os.WriteFile()
                           → .stack/data/<entity>.nix  (legacy)
                           → .stack/config.nix         (consolidated)
```

#### Data Read Flow (evaluated entities)

For entities like `variables` that include module-contributed values:

```
handleNixDataRead()
  → IsEvaluatedEntity("variables") == true
    → FlakeWatcher.GetConfig()          [server-specific cache]
      → extract entity from merged config
  → fallback: store.ReadEntity()        [pkg/nixdata]
```

### Connect-RPC (Typed API)

A parallel API surface generated from `agent.proto`. The web UI is migrating
toward these typed endpoints.

| File | Purpose |
|------|---------|
| `connect_service.go` | `AgentServiceServer` — implements the Connect-RPC `AgentService` interface. Contains handlers for project info, exec, nix eval/generate, nixpkgs search, shell status, and more. |
| `connect_handlers.go` | Additional Connect handlers: SST infrastructure, process-compose, secrets, files. |
| `connect_entities_gen.go` | **Generated** — entity CRUD handlers (`GetSecrets`, `GetApps`, etc.) auto-generated from proto definitions. Calls `s.server.readNixEntityJSON()` / `writeNixEntityJSON()` which delegate to the store. Do not edit. |
| `connect_patch.go` | `PatchNixData` RPC — patches a single value at a nested path within `config.nix`. Uses `s.server.patchConsolidatedData()` which delegates to `store.PatchConsolidatedData()`. |
| `connect_modules.go` | `EnableModule` / `DisableModule` / `ConfigureModule` RPCs for the module browser. |

### Secrets

Three backends, dispatched based on the project's `variables.backend` setting.

| File | Purpose |
|------|---------|
| `chamber.go` | **Backend dispatch.** Routes `/api/secrets/{write,read,delete,list}` to the appropriate backend (agenix or chamber). |
| `agenix.go` | Agenix (age-encrypted) secret backend. Writes `.age` files and updates `secrets.nix`. |
| `sops.go` | SOPS backend for per-environment YAML secret files (`/api/sops/*`). |
| `secrets_groups.go` | Group-based secrets — SOPS files partitioned by access-control group (`/api/secrets/group/*`). |

### Real-Time Updates

| File | Purpose |
|------|---------|
| `sse.go` | `GET /api/events` — Server-Sent Events. Broadcasts `config-changed`, `shell-status`, `packages-changed` events. `watchConfigFiles()` watches the filesystem and triggers events. |
| `flake_watcher.go` | `FlakeWatcher` — watches `.nix` files via fsnotify, re-evaluates `stackpanelConfig` and `stackpanelPackages` flake outputs on change, updates caches, and fires SSE events. |
| `shell_manager.go` | `ShellManager` — tracks devshell rebuild state. Detects when Nix files change after the last shell build and exposes staleness info to the UI. |
| `ws.go` | `GET /ws` — legacy WebSocket endpoint. Prefer HTTP + SSE for new work. |

### External Integrations

| File | Purpose |
|------|---------|
| `process_compose.go` | Proxy to the local `process-compose` API: list processes, start/stop/restart, stream logs (including WebSocket log streaming). |
| `sst.go` | SST (Serverless Stack) integration: config, deploy, status, resources, outputs, remove. |
| `nixpkgs_search.go` | `POST /api/nixpkgs/search` — searches nixpkgs for packages. Also handles installed-package listing and package metadata. |
| `registry.go` | Module registry client — fetches the remote module catalog, supports search, install, and update. |
| `security_status.go` | `GET /api/security/*` — AWS session validity, step-ca certificate status. |
| `healthchecks.go` | `GET /api/healthchecks` — aggregated health status for all configured modules (port checks, HTTP probes, etc). |

### Project Management

| File | Purpose |
|------|---------|
| `project_handlers.go` | REST handlers for `/api/project/*`: open, close, list, validate, remove, set default. |

### Utilities

| File | Purpose |
|------|---------|
| `api_handlers.go` | `handleValidateToken` and small one-off REST handlers. |
| `helpers.go` | `writeJSON()`, `writeAPI()`, `writeAPIError()`, `readJSON()`, random string generation, YAML helpers. |
| `modules.go` | Module types (`Module`, `ModuleMeta`, etc.), module config file I/O, and REST handlers for `/api/modules`. |

---

## Endpoint Quick Reference

All endpoints are registered in `server.go` → `New()`. The middleware chain is:

```
withCORS → requireAuth → requireProject → handler
```

- **Public** (no auth): `/health`, `/status`, `/pair`, `/api/project/current`, `/api/project/list`
- **Auth only** (no project needed): `/api/auth/validate`, `/api/security/*`, `/api/nixpkgs/*`, `/api/registry`
- **Auth + project**: everything else (`/api/nix/*`, `/api/secrets/*`, `/api/files/*`, `/ws`, etc.)

---

## Cookbook

### Using Nix Data from the CLI

```go
import (
    executor "github.com/darkmatter/stack/stack-go/pkg/exec"
    "github.com/darkmatter/stack/stack-go/pkg/nixdata"
)

func main() {
    exec, err := executor.New("/path/to/project", nil)
    if err != nil { panic(err) }

    store := nixdata.NewStore("/path/to/project", exec)

    // Read the apps entity
    apps, err := store.ReadEntity("apps")

    // Write a new app entry
    store.SetKey("apps", "web", map[string]any{
        "command": "npm start",
        "port":    3000,
    })

    // Patch a single field in config.nix
    store.PatchConsolidatedData("deployment.fly.organization", "my-org")
}
```

### Adding a New HTTP Endpoint

1. Write your handler as a method on `*Server` (REST) or `*AgentServiceServer` (Connect-RPC).
2. Register the route in `New()` inside `server.go` with the appropriate middleware chain.
3. If it needs proto types, define the messages in `agent.proto`, regenerate, and implement the Connect handler.
4. For data operations, use `s.store` (the `*nixdata.Store` on the server). Do not duplicate read/write logic.
5. If it modifies Nix data, fire an SSE event so the UI refreshes:
   ```go
   s.broadcastSSE(SSEEvent{Event: "config.changed", Data: map[string]any{...}})
   ```

### Adding a New Entity Type

1. Add it to `IsMapEntity()` in `pkg/nixdata/entities.go` if it is keyed by user-defined IDs.
2. Add it to `IsEvaluatedEntity()` if its final value includes module-contributed data.
3. If it has user-defined map keys, add those parent key names to `MapFieldNames()` and the TypeScript `MAP_FIELD_NAMES` set in `apps/web/src/lib/nix-data/index.ts`.
4. If it needs a Connect-RPC endpoint, add proto messages to `agent.proto` and regenerate.