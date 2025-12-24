## Nix refactor plan: shared core + thin adapters

### Goal
- **Same functionality** in both entrypoints:
  - `nix develop --impure --no-eval-cache`
  - `devenv shell`
- Make it **obvious** what is:
  - **core logic** (reusable)
  - **module adapter** (options + wiring)
- Remove duplication between `nix/modules/*` and `nix/lib/*`.

### Target layout (north star)
- **`nix/lib/core/`**: shared behavior (pure-ish functions returning `{ packages, env, shellHook/enterShell, files?, warnings? }`)
- **`nix/modules/*`**: thin adapters that:
  - define options
  - map `config.stackpanel.*` → `nix/lib/core/*`
  - merge returned attrs into devenv/Nix module outputs
- **Entrypoints**
  - `nix/stackpanel.nix`: devenv module aggregator
  - `nix/modules/devenv/devenv.nix`: devenv directory import entrypoint (obvious import path)
  - `nix/modules/devenv.nix`: compatibility shim (only if needed)
  - `flake.nix`: exports `flake.lib.*`, `flake.devenvModules.*` (and any module paths)

### Principles
- **Single source of truth**: implement behavior once (core), call it from both adapters.
- **Adapters stay tiny**: avoid duplicating computation in modules.
- **Purity by default**: impure reads must be explicit and optional.
- **Compatibility**: prefer shims/deprecations over breaking moves.

---

## Todo list

### Completed (already done)
- [x] Create shared core for global services: `nix/lib/core/global-services.nix`
- [x] Refactor `nix/lib/devshell.nix` to use shared core
- [x] Refactor `nix/modules/global-services.nix` to use shared core
- [x] Add obvious devenv import path: `nix/modules/devenv/devenv.nix`
- [x] Add compatibility shim: `nix/modules/devenv.nix`
- [x] Eval sanity checks:
  - [x] `nix eval '.#devenvModules.default'`
  - [x] `nix eval '.#lib'`
  - [x] `nix eval '.#nixosModules.default'`

### Next (core parity module-by-module) - COMPLETED
- [x] **Ports**: moved deterministic port computation into `nix/lib/core/ports.nix`; `nix/modules/ports.nix` now uses shared core.
- [x] **Caddy**: module already uses `nix/lib/caddy.nix` as the single source of truth; no duplicated behavior.
- [x] **Network / Step CA**: module already uses `nix/lib/network.nix` as the single source of truth.
- [x] **AWS**: module already uses `nix/lib/aws.nix` as the single source of truth.
- [x] **Theme / starship**: module already uses `nix/lib/theme.nix` as the single source of truth.
- [x] **IDE integration**:
  - [x] Already separates "pure generation" vs "impure merge existing settings" as explicit options (`existing-settings-path`)
  - [x] Module only wires + writes files; `nix/lib/integrations/ide.nix` generates content

### Optional (high-leverage)
- [ ] Centralize shared option types/defaults in `nix/lib/modules/options.nix` (or `nix/modules/options/`) so both adapters share one schema.
- [ ] Update docs to recommend `stackpanel/nix/modules/devenv` import path everywhere.

---

## Summary of Changes (2024-12-23)

### Files Created
- `nix/lib/core/ports.nix`: Pure port computation library with functions:
  - `computeBasePort`: Deterministic port from project name
  - `computeServicePort`: Port for a service by index
  - `computeServicesWithPorts`: Compute ports for a list of services
  - `mkServicesByKey`: Create lookup attrset by service key
  - `mkServiceEnvVars`: Generate environment variables for services
  - `mkPortsConfig`: Convenience function for full port configuration

### Files Modified
- `nix/modules/ports.nix`: Now imports and uses `nix/lib/core/ports.nix` for all computation
- `nix/lib/default.nix`: Added `ports` export for port computation utilities
- `nix/lib/devshell.nix`: Added `ports` export for mkShell users

### Architecture
The codebase now follows a consistent pattern where:
1. **Core libraries** (`nix/lib/core/*.nix`, `nix/lib/*.nix`): Pure functions that implement behavior
2. **Modules** (`nix/modules/*.nix`): Thin adapters that define options and call core libraries
