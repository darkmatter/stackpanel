## Nix refactor plan: shared core + thin adapters

### Goal
- **Primary entrypoint**: `nix develop --impure` (or `direnv allow`)
- **Devenv compatibility**: Stackpanel modules work in devenv.shells for external users
- Make it **obvious** what is:
  - **core logic** (reusable)
  - **module adapter** (options + wiring)
- Remove duplication between modules and libraries.

### Current layout (achieved)
- **`nix/stackpanel/lib/`**: shared behavior (pure-ish functions for ports, theme, IDE, services, etc.)
- **`nix/stackpanel/core/`**: core schema, state, CLI integration
- **`nix/stackpanel/modules/`**: thin adapters (options + wiring for bun, go, turbo, git-hooks, process-compose)
- **`nix/stackpanel/services/`**: service modules (aws, caddy, global-services, binary-cache)
- **`nix/stackpanel/network/`**: network modules (ports, step-ca)
- **`nix/stackpanel/ide/`**: IDE integration (vscode)
- **`nix/stackpanel/secrets/`**: secrets management (agenix, schemas, codegen)
- **Entrypoints**
  - `nix/stackpanel/default.nix`: main module aggregator
  - `nix/flake/devenv.nix`: devenv integration
  - `flake.nix`: exports `flake.lib.*`, `flake.devenvModules.*`

### Principles
- **Single source of truth**: implement behavior once (lib), call it from modules.
- **Modules stay thin**: avoid duplicating computation.
- **Purity by default**: impure reads must be explicit and optional.
- **Compatibility**: prefer shims/deprecations over breaking moves.

---

## Todo list

### Completed
- [x] Create shared core for global services: `nix/stackpanel/services/global-services.nix`
- [x] Ports module with deterministic port computation: `nix/stackpanel/network/ports.nix`
- [x] Caddy module: `nix/stackpanel/services/caddy.nix`
- [x] Network / Step CA: `nix/stackpanel/network/network.nix`
- [x] AWS Roles Anywhere: `nix/stackpanel/services/aws.nix`
- [x] Theme / starship: `nix/stackpanel/lib/theme.nix`
- [x] IDE integration: `nix/stackpanel/ide/ide.nix`
- [x] Secrets management: `nix/stackpanel/secrets/`
- [x] SST infrastructure module: `nix/stackpanel/sst/sst.nix`
- [x] Process-compose: `nix/stackpanel/modules/process-compose.nix`
- [x] Git hooks: `nix/stackpanel/modules/git-hooks.nix`
- [x] CLI state integration: `nix/stackpanel/core/state.nix`

### Optional (high-leverage)
- [ ] Centralize shared option types/defaults in `nix/stackpanel/core/options/` so both adapters share one schema.
- [ ] Update docs to recommend `nix/stackpanel` import path everywhere.

---

## Architecture (Current)

The codebase follows a consistent pattern:
1. **Libraries** (`nix/stackpanel/lib/*.nix`): Pure functions that implement behavior
2. **Core** (`nix/stackpanel/core/*.nix`): Schema definitions, state management, CLI integration
3. **Modules** (`nix/stackpanel/modules/*.nix`): Thin adapters for specific tooling (bun, go, turbo, etc.)
4. **Services** (`nix/stackpanel/services/*.nix`): Service-specific modules (aws, caddy, global-services)
5. **Network** (`nix/stackpanel/network/*.nix`): Networking modules (ports, step-ca)
6. **IDE** (`nix/stackpanel/ide/*.nix`): IDE integration (vscode workspace, terminal profiles)
7. **Secrets** (`nix/stackpanel/secrets/*.nix`): Secrets management (agenix, schemas, wrapped)
