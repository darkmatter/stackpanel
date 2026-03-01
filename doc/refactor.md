# Stackpanel Codebase Refactoring Plan

**Created**: 2026-03-01
**Status**: Planning

## Codebase Snapshot

| Category | Count | Notes |
|----------|-------|-------|
| Workspace packages | 22 | 4 apps, 16 packages, 1 generated, 1 infra |
| TypeScript source files | ~463 | Excludes node_modules, .sst/platform, dist, .next |
| Go source files | 139 | All under `apps/stackpanel-go/` |
| Nix files | 295 | Under `nix/` |
| Proto files | 28 | `packages/proto/proto/` |
| Proto-Nix schemas | 23 | `nix/stackpanel/db/schemas/` |
| Nix option files | 31 | `nix/stackpanel/core/options/` |

### Workspace Layout (actual)

```
apps/
  web/              @stackpanel/web         TanStack Start + Vite
  docs/             docs                    Next.js 16 + Fumadocs
  stackpanel-go/    stackpanel-go           Go CLI + Agent
  tui/              tui                     OpenTUI experiment

packages/
  api/              @stackpanel/api         tRPC routers
  agent-client/     @stackpanel/agent-client  Connect-RPC client
  auth/             @stackpanel/auth        Better-Auth
  config/           @stackpanel/config      Shared tsconfig only (no source)
  db/               @stackpanel/db          Drizzle ORM
  docs-content/     @stackpanel/docs-content  MDX content
  env/              (phantom)               No package.json, orphaned node_modules
  gen/env/          @gen/env                Nix-generated typed env vars
  infra/            @stackpanel/infra       SST + Alchemy IaC
  proto/            @stackpanel/proto       28 proto files, generated Go + TS types
  scripts/          @stackpanel/scripts     Shell entrypoints
  secrets/          (broken)                No package.json, barrel exports missing files
  ui/               @stackpanel/ui          Facade: re-exports ui-core + ui-web
  ui-core/          @stackpanel/ui-core     cn(), cva, clsx, twMerge, Logo, fonts
  ui-native/        @stackpanel/ui-native   Empty stub (zero components)
  ui-primitives/    @stackpanel/ui-primitives  Re-export of 27 @radix-ui/* packages
  ui-web/           @stackpanel/ui-web      16 shadcn components
  znv/              znv                     Vendored Zod env parser (patched for Zod 4)

infra/
  alchemy/          @stackpanel/alchemy     Alchemy IaC (NOT in workspace globs)
```

---

## 1. UI Package Consolidation

**Priority**: High
**Effort**: 1-2 days
**Packages affected**: `ui`, `ui-core`, `ui-web`, `ui-primitives`, `ui-native`

### Problem

Five UI packages exist where 1-2 would suffice:

```
@stackpanel/ui (facade)
  re-exports @stackpanel/ui-core (utilities)
  re-exports @stackpanel/ui-web (components)
    imports @stackpanel/ui-core
    imports @stackpanel/ui-primitives (27 Radix re-exports)
  re-exports @stackpanel/ui-native (empty stub)
```

The facade is not serving its purpose. Actual consumer imports in `apps/web/`:

| What's imported | From where | Times |
|-----------------|-----------|-------|
| CSS | `@stackpanel/ui/web.css` | 1 |
| `cn()`, `Logo` | `@stackpanel/ui-core` | 2 |
| `Field` | `@stackpanel/ui-web/field` | 2 |
| Components via facade | `@stackpanel/ui` | 0 |

The main app bypasses the facade entirely. `ui-primitives` is consumed only by `ui-web` (11 imports) and exists solely to re-export `@radix-ui/*` packages. `ui-native` has zero components -- just a `cn()` re-export and a TODO comment.

### Proposal

**Remove 3 packages, keep 2:**

| Package | Action |
|---------|--------|
| `ui-native` | Delete. Zero components, pure stub. |
| `ui-primitives` | Delete. Move its 27 `@radix-ui/*` dependencies into `ui-web/package.json`. Update 11 imports in `ui-web/src/` from `@stackpanel/ui-primitives` to `@radix-ui/*` directly. |
| `ui-core` | Keep. Contains platform-agnostic utilities (`cn`, `cva`, `clsx`, `twMerge`), the `Logo` component, fonts, and CSS. Has no Radix or React DOM dependency. |
| `ui-web` | Keep. Contains the 16 shadcn components. Depends on `ui-core` and `@radix-ui/*` directly. |
| `ui` | Delete the facade package. Consumers already import `ui-core` and `ui-web` directly. Move the CSS files (`docs.css`, `web.css`, `base.css`) into `ui-core`. |

**Result**: 5 packages down to 2 (`ui-core` + `ui-web`).

### Migration Steps

1. Move `@radix-ui/*` deps from `ui-primitives/package.json` into `ui-web/package.json`
2. In `ui-web/src/`, replace all `from '@stackpanel/ui-primitives'` with direct `from '@radix-ui/react-*'` imports
3. Move CSS files from `ui/src/` into `ui-core/src/styles/`
4. Update `apps/web/` CSS import from `@stackpanel/ui/web.css` to `@stackpanel/ui-core/styles/web.css`
5. Delete `packages/ui-native/`, `packages/ui-primitives/`, `packages/ui/`
6. Remove workspace references from any consuming `package.json` files
7. Run `bun install` and `bun run build` to verify

### Risks

**Low**. Consumer import patterns already point at `ui-core` and `ui-web` directly. The facade deletion just removes an unused indirection layer. TypeScript will catch any missed import at compile time.

If React Native support is ever needed, a new `ui-native` can be created from scratch -- the current stub provides no head start.

---

## 2. Dead/Orphan Package Cleanup

**Priority**: High
**Effort**: 30 minutes
**Packages affected**: `env`, `secrets`, `config`, `tooling/*`

### Inventory

| Item | Location | Problem | Action |
|------|----------|---------|--------|
| `packages/env/` | `packages/env/` | No `package.json`. Only orphaned `node_modules/`. Real env package is `packages/gen/env/`. | Delete directory |
| `packages/secrets/` | `packages/secrets/` | No `package.json`. `src/index.ts` barrel-exports `./docs` and `./web` which don't exist. | Delete directory |
| `packages/config/` | `packages/config/` | `package.json` exists but package contains zero source files. Only a shared `tsconfig.base.json`. | Keep, but document purpose in its `package.json` description field |
| `tooling/*` workspace glob | `package.json` | Directory does not exist. Dead workspace reference. | Remove from workspace globs |
| `infra/alchemy/` | `infra/alchemy/` | Valid 472-line IaC file but not in workspace globs. Declares itself as `@stackpanel/alchemy`. Overlaps with `packages/infra/`. | Consolidate into `packages/infra/` |

### Steps

1. `rm -rf packages/env packages/secrets`
2. Remove `"tooling/*"` from `workspaces.packages` in root `package.json`
3. Move `infra/alchemy/index.ts` and its dependencies into `packages/infra/`. Merge `package.json` deps. Remove `infra/alchemy/`.
4. Add `"description": "Shared TypeScript configuration"` to `packages/config/package.json`
5. `bun install` to update lockfile

### Infra Consolidation Detail

`packages/infra/` already contains SST config, Alchemy modules, and AWS infrastructure code (11 source files). `infra/alchemy/index.ts` (472 lines) defines the top-level Alchemy resources (DevenvPostgres, DevenvRedis, Cloudflare Workers, etc.). These belong together.

After consolidation:
```
packages/infra/
  src/
    alchemy.ts          # Moved from infra/alchemy/index.ts
    modules/            # Existing: aws-secrets, deployment, iam
    ...
  package.json          # Merged deps from both
```

The `infra/scripts/` directory (shell scripts for DB provisioning, container sizing) can remain at `infra/scripts/` -- these are operational scripts, not workspace packages.

---

## 3. Nix Option File Consolidation

**Priority**: Medium
**Effort**: 1-2 days
**Location**: `nix/stackpanel/core/options/`

### Current State

31 files, 5,891 total lines. Size distribution:

**Tiny files (under 60 lines) -- consolidation candidates:**

| File | Lines | Content |
|------|-------|---------|
| `step-ca.nix` | 21 | Proto-schema wrapper, one-liner |
| `binary-cache.nix` | 29 | `enable` + `cachix.{enable, cache}` |
| `cli.nix` | 31 | `enable` + `quiet` |
| `theme.nix` | 40 | Proto-schema wrapper |
| `aws.nix` | 48 | Proto-derived + few Nix options |
| `users.nix` | 50 | Proto-derived user submodule |
| `state.nix` | 51 | `file`, `devenv`, `custom` options |
| `ci.nix` | 58 | `enable`, `github.enable`, `github.workflows` |
| `motd.nix` | 60 | `enable`, `commands`, `features`, `hints` |
| `dns.nix` | ~50 | DNS configuration |

**Large files -- leave alone (each is a cohesive single concern):**

| File | Lines | Content |
|------|-------|---------|
| `modules.nix` | 661 | Module system schema, registries |
| `extensions.nix` | 625 | Extension system, panels, per-app computed data |
| `healthchecks.nix` | 532 | Healthcheck types (script/http/tcp/nix) |
| `apps.nix` | 529 | App submodule type, framework support, computed ports |
| `panels.nix` | 417 | UI panel definitions, field types, form actions |
| `core.nix` | 352 | Root options: enable, root, dirs, direnv |
| `devshell.nix` | 314 | Shell env: packages, hooks, env, path |
| `services.nix` | 250 | Canonical service type system |
| `checks.nix` | 232 | Flake check schema |

### Proposal

Merge the 10 tiny files into 3 domain-grouped files:

| New File | Merges | Combined Lines |
|----------|--------|----------------|
| `infrastructure.nix` | `aws.nix` (48) + `step-ca.nix` (21) + `dns.nix` (~50) + `binary-cache.nix` (29) | ~148 |
| `data.nix` | `users.nix` (50) + `theme.nix` (40) + `variables.nix` + `variables-backend.nix` + `tasks.nix` | ~250 |
| `runtime.nix` | `cli.nix` (31) + `state.nix` (51) + `motd.nix` (60) + `ci.nix` (58) | ~200 |

Leave all files over 200 lines untouched. Update `default.nix` import list accordingly.

**Result**: 31 files down to ~21. No logic changes, pure file reorganization.

### Why Not Fewer Files?

The large files (`modules.nix` at 661 lines, `extensions.nix` at 625 lines, etc.) are each a self-contained concern with their own submodule type definitions. Merging them would create 1,000+ line mega-files that are harder to navigate. The "one concern per file" pattern is correct for these -- the problem was only with the trivially small files.

---

## 4. Nix Structural Cleanup

**Priority**: Medium
**Effort**: 1 day
**Locations**: `nix/stackpanel/core/`, `nix/stackpanel/apps/`

### 4.1 Remove Legacy State Serialization

**File**: `nix/stackpanel/core/state.nix` (118 lines)

This is the legacy state file generator that writes `stackpanel.json` via shell hook. It is disabled when `cli.enable = true` (which is the default path -- `core/cli.nix` passes the config JSON to the Go CLI instead). Both files serialize the same state structure.

**Action**: Delete `state.nix`. Remove its import from `core/default.nix`. If CLI mode is always enabled, this code path is dead. If there is a scenario where CLI is disabled, document it and keep the file -- but add a comment explaining the relationship.

**Prerequisite**: Verify that `stackpanel.cli.enable` defaults to `true` and no user configurations set it to `false`.

### 4.2 Clarify the Two "services" Directories

**Current state**:
- `nix/stackpanel/core/services/` (3 files, 366 lines) -- Pure library functions: `mkService`, `mkGlobalPostgres`, `mkGlobalServices`
- `nix/stackpanel/services/` (10 entries) -- Module implementations: AWS, Caddy, global-services wiring, postgres/, redis/, minio/

These are **not duplicates** -- they follow the intended lib-vs-module pattern. But having two directories named "services" at different levels creates confusion.

**Action**: Rename `core/services/` to `core/lib/services/` and move its 3 files there. The `core/lib/` directory already exists (2 files: `evalconfig.nix`, `envvars.nix`), making this a natural fit:

```
core/lib/
  evalconfig.nix       # (existing) Config evaluation helper
  envvars.nix          # (existing) Environment variable generation (593 lines)
  services.nix         # (moved from core/services/) Service registry
  global-services.nix  # (moved from core/services/) Pure service factory functions
```

Update the import in `core/services/default.nix` (which becomes `core/lib/default.nix` or just update the references).

### 4.3 Remove Redundant Import in apps/apps.nix

**File**: `nix/stackpanel/apps/apps.nix`, line 128

This file imports `../core/options` even though the parent aggregator (`nix/stackpanel/default.nix`) already imports `./core` which includes `./options`. Nix deduplicates the import, so there is no runtime issue, but it obscures the dependency graph and suggests `apps/apps.nix` is self-sufficient when it is not.

**Action**: Remove the redundant `imports = [ ../core/options ];` line. The options are already available through the module system's evaluation context.

---

## 5. Workspace Hygiene

**Priority**: Medium
**Effort**: 30 minutes
**Location**: Root `package.json`, various

### Current Workspace Globs

```json
"workspaces": {
  "packages": [
    "apps/*",
    "packages/*",
    "packages/gen/*",
    "tooling/*"
  ]
}
```

### Issues

| Issue | Fix |
|-------|-----|
| `tooling/*` references nonexistent directory | Remove from globs |
| `infra/alchemy/` declares `@stackpanel/alchemy` but is not in any workspace glob | Consolidate into `packages/infra/` (see Section 2) |
| `packages/env/` has no `package.json` but sits inside `packages/*` glob | Delete directory (see Section 2) |
| `packages/secrets/` has no `package.json` but sits inside `packages/*` glob | Delete directory (see Section 2) |

### Vendored Package Documentation

`packages/znv/` is a vendored fork of the `znv` library, patched for Zod 4 compatibility (upstream requires Zod 3). This is a legitimate vendoring decision but should be documented:

**Action**: Add a `"vendorReason"` field (or a comment in the README) explaining why it's vendored:
> Vendored from github.com/lostfictions/znv v0.5.0. Patched to use Zod 4 (catalog:) instead of Zod 3. Upstream does not yet support Zod 4.

### Post-Cleanup Workspace State

After completing Sections 1-5:

```json
"workspaces": {
  "packages": [
    "apps/*",
    "packages/*",
    "packages/gen/*"
  ]
}
```

```
packages/
  api/              @stackpanel/api
  agent-client/     @stackpanel/agent-client
  auth/             @stackpanel/auth
  config/           @stackpanel/config        (tsconfig only, documented)
  db/               @stackpanel/db
  docs-content/     @stackpanel/docs-content
  gen/env/          @gen/env
  infra/            @stackpanel/infra          (consolidated with infra/alchemy/)
  proto/            @stackpanel/proto
  scripts/          @stackpanel/scripts
  ui-core/          @stackpanel/ui-core
  ui-web/           @stackpanel/ui-web
  znv/              znv                        (vendored, documented)
```

**13 packages** (down from 18 under `packages/` + 1 orphan under `infra/`).

---

## Execution Order

These changes are independent and can be done in any order. Recommended sequencing by risk (lowest first):

| Order | Section | Effort | Risk | Why This Order |
|-------|---------|--------|------|----------------|
| 1 | Dead/orphan cleanup (Section 2) | 30 min | None | Deleting broken/empty directories. Cannot break anything. |
| 2 | Workspace hygiene (Section 5) | 30 min | None | Removing dead globs and adding docs. |
| 3 | UI consolidation (Section 1) | 1-2 days | Low | Import updates are mechanical. TypeScript catches errors. |
| 4 | Nix structural cleanup (Section 4) | 1 day | Low | File moves within Nix. `nix develop --impure` validates. |
| 5 | Nix option consolidation (Section 3) | 1-2 days | Low | Pure file merges. `nix develop --impure` validates. |

**Total effort**: 3-5 days.

**Validation after each step**: `bun install && bun run build && nix develop --impure` (per AGENTS.md development guidelines).

---

## What This Plan Does Not Cover

These were in the previous version of this document but are not justified by the actual codebase data:

| Previous Proposal | Why Excluded |
|-------------------|--------------|
| Proto file consolidation (192 to 50) | Actual count is 28 files, already reasonable |
| Build system overhaul (7 tools to 5) | Tool count is appropriate for a polyglot monorepo (Nix + Turborepo + Vite + Bun + Air) |
| Replace Next.js with TanStack Start for docs | Fumadocs is purpose-built for documentation with MDX, search, and TypeScript API doc generation |
| Directory structure flattening | No phantom `fumadocs/` directory exists. Actual depth (4-5 levels) is manageable. |
| Unified `build.config.ts` | Would create a third source of truth alongside Nix port computation and `stackpanel.json` state file |
| Nix adapter unification | The flake-parts and devenv adapters serve different module systems and cannot be trivially merged |
