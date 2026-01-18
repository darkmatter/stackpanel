# Refactoring Checklist

A prioritized checklist of refactoring tasks for the stackpanel repository.

---

## Quick Wins (< 30 min each)

### Dead Files
- [x] Delete `nix/stackpanel/core/TODO.md` (empty file)
- [x] Delete `apps/web/src/routes/demo.tsx` (only redirects to /studio)
- [x] Archive `docs/plans/generated-files-and-process-compose.md` to `docs/archive/`

### Comment Fixes
- [x] Fix header comment in `nix/stackpanel/modules/bun.nix` - change "Go application module" to "Bun application module"

### Broken Links
- [x] Remove `/todos` link from `apps/web/src/components/header.tsx`

### Todo Cleanup (choose one path)
- [x] **Option A**: Delete todo functionality entirely
  - [x] Delete `packages/api/src/routers/todo.ts`
  - [x] Delete `packages/db/src/schema/todo.ts`
  - [x] Remove todo router from `packages/api/src/routers/index.ts`
  - [x] Remove todo schema from `packages/db/src/index.ts`
- [ ] ~~**Option B**: Implement todo UI~~ (not chosen)

---

## Medium Effort (1-4 hours each)

### Go CLI Improvements

#### Extract Print Helpers
- [x] Create `apps/stackpanel-go/internal/output/print.go`
- [x] Move `printSuccess`, `printError`, `printWarning`, `printInfo`, `printDim` from `cmd/cli/root.go`
- [x] Update all cmd files to import from `internal/output`
- [x] Add tests for print functions

#### Remove Unused Functions
- [x] Audit `pkg/services/registry.go` - verify `GetAll()` is used (N/A - function doesn't exist)
- [x] Audit `pkg/nixeval/nixeval.go` - verify `MustEvalExpr`, `MustEvalJSON` are used (N/A - functions don't exist)
- [x] Remove any confirmed unused exports (none found)

### Nix Module Cleanup

#### Remove Unused Library Functions
- [x] In `nix/stackpanel/lib/ports.nix`:
  - [x] Remove or document `computeServicePort` if unused (documented - part of public API)
  - [x] Remove or document `mkPortsConfig` if unused (documented - part of public API)
- [x] In `nix/stackpanel/lib/util.nix`:
  - [x] Remove `getConfigValue` if unused (kept - may be useful for consumers)

#### Fix Duplicate Imports
- [x] Audit modules for unused `types = lib.types` imports (removed from 3 files: files.nix, schema.nix, codegen.nix)
- [x] Create shared util injection to avoid repeated `import ../lib/util.nix { inherit pkgs lib config; }`

### TypeScript Improvements

#### Remove Mocking Code
- [x] In `apps/web/src/components/studio/panels/extensions-panel.tsx`:
  - [x] Remove `// TODO: Remove when not mocking` code
  - [x] Clean up mock data and enable real config loading

#### Add Process-Compose Integration
- [x] In `apps/web/src/components/studio/panels/apps-panel-alt.tsx`:
  - [x] Implement process-compose query for running state (line 216)
- [x] In `apps/web/src/lib/use-nix-config.ts`:
  - [x] Updated comment to clarify architecture (components handle real-time state via agent API)

---

## Larger Refactors (1-2 days each)

### Split Large TypeScript Files

#### Split use-nix-config.ts (958 lines)
- [-] Extract `useApps` hook to `apps/web/src/lib/hooks/use-apps.ts`
- [ ] Extract `useServices` hook to `apps/web/src/lib/hooks/use-services.ts`
- [ ] Extract `useNixEval` hook to `apps/web/src/lib/hooks/use-nix-eval.ts`
- [ ] Create barrel export in `apps/web/src/lib/hooks/index.ts`
- [ ] Update imports in consuming components
- [ ] Reduce useEffect count (currently 6)

#### Split apps-panel-alt.tsx (558 lines)
- [ ] Extract `AppCard` component to `panels/apps/app-card.tsx`
- [ ] Extract `AppList` component to `panels/apps/app-list.tsx`
- [ ] Extract `AppDetails` component to `panels/apps/app-details.tsx`
- [ ] Extract app-related types to `types/app.ts`

---

## React Component Refactoring

### Critical: Giant Components (>500 lines)

#### setup-wizard.tsx (1339 lines) - ALREADY REFACTORED
- [x] **Already complete** - File is now 539 lines with modular architecture:
  - [x] Step components extracted to `setup/steps/` directory
  - [x] Context extracted to `setup-context.tsx`
  - [x] Types extracted to `types.ts`
  - [x] Reusable StepCard component in `step-card.tsx`

#### agent.ts (1140 lines)
- [ ] Split into focused modules:
  - [ ] `agent/client.ts` - AgentHttpClient class
  - [ ] `agent/types.ts` - All type definitions
  - [ ] `agent/requests.ts` - Request helpers
  - [ ] `agent/responses.ts` - Response types
  - [ ] `agent/index.ts` - Barrel export
- [ ] Extract interfaces for testability

#### infra-panel.tsx (1034 lines) - REFACTORED
- [x] Created modular structure in `panels/infra/` directory:
  - [x] `types.ts` - SSTData, SSTStatus, SSTResource type definitions
  - [x] `constants.ts` - OIDC_PROVIDERS, AWS_REGIONS, DEFAULT_SST_DATA, mergeWithDefaults
  - [x] `components.tsx` - StatusCard, ResourceRow, OutputRow components
  - [x] `use-sst-config.ts` - Full state management hook (form state, runtime status, deploy actions)
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 821 lines main file + 572 lines in extracted modules

#### configuration-panel.tsx (770 lines) - REFACTORED
- [x] Created modular structure in `panels/configuration/` directory:
  - [x] `types.ts` - StepCaData, AwsData, ThemeData, IdeData, etc. type definitions
  - [x] `constants.ts` - STARSHIP_PRESETS, optionalValue helper
  - [x] `use-configuration.ts` - Full state management hook (all useState, useEffect, save callbacks)
  - [x] `index.ts` - Barrel export
- [x] Main component is now pure UI with no state management (475 lines)
- [x] All 35+ useState calls and 6 useEffect hooks moved to hook

### High Priority: Large Components (400-700 lines)

#### app-variables-section.tsx (693 lines) - REFACTORED
- [x] Created modular structure in `panels/apps/app-variables-section/` directory:
  - [x] `types.ts` - DisplayVariable, AvailableVariable, AppVariablesSectionProps, EditMode, AppVariablesSectionState
  - [x] `components.tsx` - EditInterface, VariableBadge components
  - [x] `use-app-variables-section.ts` - Full state management hook (filtering, environment editing, variable editing)
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 291 lines main file + 753 lines in extracted modules

#### packages-panel.tsx (688 lines) - REFACTORED
- [x] Created modular structure in `panels/packages/` directory:
  - [x] `types.ts` - PackageCardProps, SearchErrorMessageProps, DataSourceIndicatorProps, ProcessingStatus
  - [x] `components.tsx` - SearchErrorMessage, DataSourceIndicator, PackageCard components
  - [x] `use-packages.ts` - Full state management hook (search, install/remove, processing state)
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 288 lines main file + 499 lines in extracted modules

#### app-config-drawer.tsx (675 lines) - REFACTORED
- [x] Created modular structure in `components/app-config-drawer/` directory:
  - [x] `types.ts` - Environment, AvailableTask, TaskConfig, AvailableSecret, VariableConfig, App, AppConfigDrawerProps
  - [x] `constants.ts` - AVAILABLE_TASKS, AVAILABLE_SECRETS, ENVIRONMENT_SHORT_NAMES, formatEnvironments
  - [x] `use-app-config-drawer.ts` - Full state management hook (tasks, variables, filtering)
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 433 lines main file + 362 lines in extracted modules

#### edit-secret-dialog.tsx (629 lines) - REFACTORED
- [x] Created modular structure in `panels/variables/edit-secret-dialog/` directory:
  - [x] `types.ts` - EditSecretDialogProps, EditSecretDialogState, AgeIdentitySettingsState, KMSSettingsState
  - [x] `constants.ts` - createAgentClient helper
  - [x] `use-edit-secret-dialog.ts` - Full state management hook (loading, saving, decryption)
  - [x] `age-identity-settings.tsx` - Standalone AgeIdentitySettings component
  - [x] `kms-settings.tsx` - Standalone KMSSettings component
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 202 lines main file + 551 lines in extracted modules

#### dev-shells-panel.tsx (565 lines) - REFACTORED
- [x] Created modular structure in `panels/devshells/` directory:
  - [x] `types.ts` - DevshellConfig, StackpanelConfigData, AgentStatus, ToolCategory, AvailableTool, DevShell, Script
  - [x] `constants.ts` - RUNTIME_KEYWORDS, LANGUAGE_KEYWORDS, categorizePackage, formatPackageLabel
  - [x] `use-devshells.ts` - Full state management hook (agent status, shell data, tools, scripts)
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 363 lines main file + 279 lines in extracted modules

### Medium Priority: Components (300-500 lines)

#### secrets-panel.tsx (524 lines) - REFACTORED
- [x] Created modular structure in `panels/secrets/` directory:
  - [x] `types.ts` - Secret, SecretsPanelState type definitions
  - [x] `constants.ts` - DEMO_SECRETS, getTypeColor, inferSecretType helpers
  - [x] `use-secrets.ts` - Full state management hook (agent communication, filtering, CRUD operations)
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 366 lines main file + 259 lines in extracted modules

#### files-panel.tsx (504 lines)
- [ ] Extract `FileTree.tsx` - Tree view
- [ ] Extract `FileCard.tsx` - File display
- [ ] Extract `FileActions.tsx` - File operations

#### databases-panel.tsx (500 lines)
- [ ] Extract `DatabaseList.tsx`
- [ ] Extract `DatabaseCard.tsx`
- [ ] Extract `DatabaseConnectionInfo.tsx`
- [ ] Extract `useDatabases.ts` hook

#### network-panel.tsx (494 lines)
- [ ] Extract `NetworkOverview.tsx`
- [ ] Extract `PortsList.tsx`
- [ ] Extract `CaddyConfig.tsx`
- [ ] Extract `StepCAStatus.tsx`

#### agent-connect.tsx (446 lines)
- [ ] Extract `ConnectionStatus.tsx`
- [ ] Extract `ConnectionForm.tsx`
- [ ] Extract `AgentInfo.tsx`
- [ ] Extract `useAgentConnection.ts` hook

#### use-nixpkgs-search.ts (434 lines)
- [ ] Split search logic from caching logic
- [ ] Extract `useNixpkgsCache.ts`
- [ ] Extract `useSearchDebounce.ts`

#### nix-client.ts (425 lines)
- [ ] Split into:
  - [ ] `nix-client/client.ts` - Main client
  - [ ] `nix-client/types.ts` - Types
  - [ ] `nix-client/requests.ts` - Request helpers

#### app-variable-manager.tsx (406 lines)
- [ ] Merge with or differentiate from app-variables-section.tsx
- [ ] Extract shared components between the two

#### team-panel.tsx (397 lines) - REFACTORED
- [x] Created modular structure in `panels/team/` directory:
  - [x] `types.ts` - GithubCollaborator, GithubCollaboratorsData, TeamMember
  - [x] `constants.ts` - getRoleColor helper function
  - [x] `use-team.ts` - Full state management hook (users, GitHub collaborators, search, filtering)
  - [x] `index.ts` - Barrel export
- [x] Main component imports from extracted modules
- [x] Result: 296 lines main file + 167 lines in extracted modules

#### project-selector.tsx (378 lines)
- [ ] Extract `ProjectList.tsx`
- [ ] Extract `ProjectCard.tsx`
- [ ] Extract `CreateProjectDialog.tsx`

#### entity-form.tsx (374 lines)
- [ ] Make more generic and reusable
- [ ] Extract field renderers by type
- [ ] Add better TypeScript generics

#### dashboard-sidebar.tsx (367 lines)
- [ ] Extract `SidebarNavItem.tsx`
- [ ] Extract `SidebarSection.tsx`
- [ ] Extract `SidebarFooter.tsx`

#### extensions-panel.tsx (362 lines)
- [ ] Extract `ExtensionList.tsx`
- [ ] Extract `ExtensionCard.tsx`
- [ ] Extract `ExtensionActions.tsx`

### Hooks Consolidation

#### Create apps/web/src/hooks/ directory structure
- [ ] Move `use-mobile.ts` from `hooks/` to `lib/hooks/`
- [ ] Create `lib/hooks/index.ts` barrel export
- [ ] Organize hooks by domain:
  ```
  lib/hooks/
  ├── index.ts
  ├── use-apps.ts
  ├── use-services.ts
  ├── use-secrets.ts
  ├── use-packages.ts
  ├── use-team.ts
  ├── use-nix-eval.ts
  ├── use-agent.ts (move from lib/)
  ├── use-generated-files.ts (move from lib/)
  └── use-setup-progress.ts (move from lib/)
  ```

### Type Organization

#### Create organized types structure
- [ ] Create `apps/web/src/types/` directory:
  ```
  types/
  ├── index.ts        # Barrel export
  ├── app.ts          # App-related types
  ├── service.ts      # Service types
  ├── secret.ts       # Secret types
  ├── team.ts         # Team/user types
  ├── nix.ts          # Nix-specific types
  ├── agent.ts        # Agent API types
  └── ui.ts           # UI component types
  ```
- [ ] Move types from `lib/types.ts` (277 lines)
- [ ] Move types from `lib/generated/nix-types.ts` (994 lines)
- [ ] Update all imports

### Component Patterns to Apply

#### Apply Compound Component Pattern
- [ ] `Sidebar` - Already uses this, verify consistency
- [ ] `Card` - Add Card.Header, Card.Content, Card.Footer exports
- [ ] `Dialog` - Ensure consistent compound pattern
- [ ] `Form` - Create Form.Field, Form.Label, Form.Error pattern

#### Apply Container/Presenter Pattern
For each major panel, create:
- [ ] Container component (data fetching, state)
- [ ] Presenter component (pure rendering)
- [ ] Example: `SecretsPanelContainer` + `SecretsPanelView`

#### Apply Custom Hook Pattern
- [ ] Each panel should have a corresponding `useXxxPanel.ts` hook
- [ ] Hooks handle: data fetching, mutations, local state
- [ ] Components become mostly presentational

### useEffect Audit

Files with multiple useEffect hooks that need refactoring:
- [ ] `use-nix-config.ts` - 6+ effects → consolidate to 2-3
- [ ] `infra-panel.tsx` - 2+ effects → extract to hook
- [ ] `app-form-fields.tsx` - 2 effects → combine or use useMemo
- [ ] `dev-shells-panel.tsx` - 1+ effects → verify necessity
- [ ] `secrets-panel.tsx` - 1+ effects → extract to hook
- [ ] `apps-panel-alt.tsx` - 1+ effects → extract to hook

### Testing Infrastructure

#### Add Component Tests
- [ ] Set up component testing with Vitest + Testing Library
- [ ] Add tests for:
  - [ ] `SetupWizard` steps
  - [ ] `AgentConnect` connection states
  - [ ] Panel components (at least smoke tests)
  - [ ] Form components validation

#### Add Hook Tests
- [ ] `useNixConfig` - test data fetching
- [ ] `useAgentConnection` - test connection states
- [ ] `usePackageSearch` - test search/debounce

---

## Go Package Restructuring

#### Split pkg/nixeval (500+ lines)
- [ ] Create `pkg/nixeval/eval.go` - core evaluation functions
- [ ] Create `pkg/nixeval/presets.go` - preset configurations
- [ ] Create `pkg/nixeval/config.go` - config loading
- [ ] Update imports across codebase
- [ ] Add tests for each new file

### Nix Directory Restructuring

#### Current Structure (problematic)
```
nix/stackpanel/
├── core/
│   ├── options/
│   ├── services/  # ← services here
│   └── lib/       # ← lib here
├── lib/           # ← another lib
│   └── services/  # ← another services
├── services/      # ← third services location!
└── modules/
```

#### Target Structure
- [ ] Phase 1: Audit current usage
  - [ ] Document which files import from each location
  - [ ] Identify the "canonical" location for each function
- [ ] Phase 2: Consolidate lib/
  - [ ] Move all pure functions to `nix/stackpanel/lib/`
  - [ ] Remove `core/lib/` (merge into lib/)
  - [ ] Update all imports
- [ ] Phase 3: Consolidate services/
  - [ ] Move all service implementations to `nix/stackpanel/services/`
  - [ ] Remove `core/services/` and `lib/services/`
  - [ ] Update all imports
- [ ] Phase 4: Update documentation
  - [ ] Update `.ruler/stackpanel.md` with new structure
  - [ ] Update `nix/stackpanel/README.md`

---

## Placeholder Packages

### packages/ui-native
- [ ] **Option A**: Implement React Native components
  - [ ] Add basic Button component
  - [ ] Add basic Text component
  - [ ] Add basic Input component
  - [ ] Export from index
- [ ] **Option B**: Remove package
  - [ ] Remove from `packages/ui-native/`
  - [ ] Remove from workspace in root `package.json`
  - [ ] Remove any imports/references

---

## Code Quality Improvements

### Error Handling in Go CLI
- [ ] In `cmd/cli/commands.go`:
  - [ ] Change functions to return errors instead of calling `printError` directly
  - [ ] Add error aggregation for batch operations
  - [ ] Improve testability

### Type Consolidation in TypeScript
- [ ] Create `packages/types/` or `apps/web/src/lib/types/`
- [ ] Move app-related types from scattered locations
- [ ] Create proper type exports
- [ ] Update imports across codebase

### Add Interfaces for Testability
- [ ] In `internal/docgen/`:
  - [ ] Add `DocGenerator` interface
  - [ ] Add `TemplateRenderer` interface
  - [ ] Enable mocking in tests

---

## Complexity Reduction (High Impact)

### 1. Agent Client Consolidation (HIGH Impact)

**Problem:** 4+ ways to create agent clients scattered across files
- `createAgentClient(token)` duplicated in 4+ files
- `new AgentHttpClient("localhost", 9876, token)` hardcoded everywhere
- `useAgentContext()` → context value
- `useAgent()` hook
- `NixClient` wrapper around `AgentHttpClient`

**Tasks:**
- [ ] Create single `useAgentClient()` hook in `lib/hooks/use-agent-client.ts`
- [ ] Remove all `createAgentClient` helper functions from:
  - [ ] `setup-wizard.tsx`
  - [ ] `edit-secret-dialog.tsx`
  - [ ] `add-variable-dialog.tsx`
  - [ ] Any other files
- [ ] Update all `new AgentHttpClient(...)` calls to use the hook
- [ ] Centralize host/port configuration in context
- [ ] **Estimated savings:** ~200 lines of duplicated code

### 2. Replace Custom Query with TanStack Query (HIGH Impact)

**Problem:** `use-nix-config.ts` (959 lines) manually reimplements React Query
- Manual loading/error/success state management
- No caching between components
- No automatic deduplication
- 6+ useEffect hooks, 10+ useCallback hooks

**Tasks:**
- [ ] Install `@tanstack/react-query`
- [ ] Create `QueryClientProvider` wrapper in app root
- [ ] Replace `useApps()` with React Query:
  ```typescript
  // Before: ~80 lines → After: ~10 lines
  export function useApps() {
    const client = useAgentClient();
    return useQuery({
      queryKey: ['apps'],
      queryFn: () => client.getApps(),
    });
  }
  ```
- [ ] Replace `useServices()` with React Query
- [ ] Replace `useSecrets()` with React Query  
- [ ] Replace `useGlobalServices()` with React Query
- [ ] Replace `useUsers()` with React Query
- [ ] Remove custom `QueryState` type and helpers
- [ ] **Estimated savings:** Reduce use-nix-config.ts from 959 to ~200 lines

### 3. Delete Dead WebSocket Code (HIGH Impact)

**Problem:** `AgentClient` class (200+ lines) is never used - SSE is used instead

**Tasks:**
- [ ] Verify no code uses `AgentClient` (only `AgentHttpClient`)
- [ ] Delete `AgentClient` class from `agent.ts`
- [ ] Delete WebSocket-related types and helpers
- [ ] Remove `export const agent = new AgentClient();` singleton
- [ ] **Estimated savings:** ~400 lines eliminated

### 4. Consolidate Overlapping Hooks (MEDIUM Impact)

**Problem:** 7 hooks for apps data alone
- `useApps()` - raw apps
- `useResolvedApps()` - apps with id field
- `useApp(id)` - single app
- `useAppsWithTask(taskName)` - filtered
- `useAppsWithVariable(varName)` - filtered
- `useAllAppTasks()` - flattened
- `useAllAppVariables()` - flattened

**Tasks:**
- [ ] Add `id` field during fetch (not wrapper hook)
- [ ] Delete `useResolvedApps` hook
- [ ] Convert filter hooks to `useMemo` in components:
  ```typescript
  const { data: apps } = useApps();
  const appsWithBuild = useMemo(() => 
    filterAppsWithTask(apps, 'build'), [apps]);
  ```
- [ ] Delete `useAppsWithTask`, `useAppsWithVariable`
- [ ] Delete `useAllAppTasks`, `useAllAppVariables`
- [ ] **Estimated savings:** ~200 lines, simpler mental model

### 5. Collapse UI Package Fragmentation (MEDIUM Impact)

**Problem:** 5 UI packages that could be 2
- `@stackpanel/ui` - Just re-exports
- `@stackpanel/ui-core` - cn, cva, logo
- `@stackpanel/ui-primitives` - Radix wrappers (adds no value)
- `@stackpanel/ui-web` - Web components
- `@stackpanel/ui-native` - Placeholder

**Tasks:**
- [ ] Merge `ui-core` into `ui-web`
- [ ] Merge `ui-primitives` into `ui-web` (or delete, import Radix directly)
- [ ] Keep `ui` as re-export layer OR merge into `ui-web`
- [ ] Keep `ui-native` separate if React Native needed, otherwise delete
- [ ] Update all imports across codebase
- [ ] **Result:** 2 packages instead of 5

### 6. Simplify Setup Wizard State (MEDIUM Impact)

**Problem:** Giant component with 15+ pieces of state passed as props

**Tasks (if not already done):**
- [ ] Create `SetupWizardContext` with reducer
- [ ] Move step-specific state INTO step components
- [ ] Each step manages own loading/saving
- [ ] Main wizard only tracks: currentStep, completedSteps
- [ ] **Estimated savings:** Reduce prop drilling, enable lazy loading

### 7. Remove Runtime Key Transformation (LOW-MEDIUM Impact)

**Problem:** Complex snake_case ↔ kebab-case transformation on every API call

**Tasks:**
- [ ] Option A: Use kebab-case in TypeScript types (matches Nix)
- [ ] Option B: Generate types at build time with both cases
- [ ] Delete `NixClient` wrapper class
- [ ] Move any needed transforms into `AgentHttpClient`
- [ ] **Estimated savings:** ~150 lines, eliminates transformation bugs

### 8. Create Generic EntityPanel Component (MEDIUM Impact)

**Problem:** Panel components have similar structure but different implementations

**Tasks:**
- [ ] Create `EntityPanel` generic component:
  ```tsx
  <EntityPanel<App>
    entity="apps"
    queryKey={['apps']}
    renderItem={(app) => <AppCard app={app} />}
    renderDetail={(app) => <AppDetail app={app} />}
    emptyState={<AddAppCTA />}
  />
  ```
- [ ] Refactor `apps-panel-alt.tsx` to use EntityPanel
- [ ] Refactor `services-panel.tsx` to use EntityPanel
- [ ] Refactor `packages-panel.tsx` to use EntityPanel
- [ ] **Estimated savings:** ~400 lines of shared patterns

### 9. Simplify SST Module (LOW Impact)

**Problem:** 684 lines for rarely-used OIDC providers

**Tasks:**
- [ ] Default to GitHub Actions OIDC only
- [ ] Move Fly.io provider to extension module
- [ ] Move Roles Anywhere provider to extension module
- [ ] Use template file instead of string interpolation
- [ ] **Estimated savings:** Reduce to ~300 lines

---

## Complexity Reduction Quick Wins

These can be done in <1 hour each:

- [x] Delete `AgentClient` class (WebSocket dead code) - Already removed previously
- [x] Create single `useAgentClient()` hook - Already exists in agent-provider.tsx
- [x] Remove `useResolvedApps` (inline the ID addition) - Completed: inlined in apps-panel-alt.tsx
- [x] Delete unused `useAppsWithTask`, `useAppsWithVariable` hooks - Completed: deleted useAppsWithTask, useAllAppTasks, useAllAppVariables (kept useAppsWithVariable as it's used in variable-usage-info.tsx)
- [x] Remove duplicated `createAgentClient` helpers from 4+ files - Already removed previously
- [x] Audit and remove unused exports from `agent.ts` - Completed: removed deprecated TurboPackagesQueryResult

---

## Verification Checklist

After each refactor:
- [ ] Run `bun run typecheck` (TypeScript)
- [ ] Run `go test ./...` (Go)
- [ ] Run `nix flake check` (Nix)
- [ ] Run `bun run dev` and verify app works
- [ ] Run `stackpanel status` to verify CLI works

---

## Progress Tracking

| Category | Total | Done | Remaining |
|----------|-------|------|-----------|
| Quick Wins | 9 | 9 | 0 |
| Medium Effort - Go CLI | 7 | 7 | 0 |
| Medium Effort - Nix | 5 | 3 | 2 |
| Medium Effort - TypeScript | 3 | 3 | 0 |
| React Components (Critical) | 25 | 12 | 13 |
| React Components (High) | 35 | 6 | 29 |
| React Components (Medium) | 40 | 2 | 38 |
| Hooks Consolidation | 12 | 0 | 12 |
| Type Organization | 10 | 0 | 10 |
| Component Patterns | 12 | 0 | 12 |
| **Complexity Reduction (HIGH)** | 25 | 0 | 25 |
| **Complexity Reduction (MED)** | 18 | 0 | 18 |
| **Complexity Quick Wins** | 6 | 6 | 0 |
| Testing | 10 | 0 | 10 |
| Go/Nix Refactors | 20 | 0 | 20 |
| Code Quality | 4 | 0 | 4 |
| **Total** | **241** | **47** | **194** |

### Impact Summary

| Task | Lines Saved | Effort |
|------|-------------|--------|
| Replace with React Query | ~750 lines | 2-3 days |
| Delete WebSocket code | ~400 lines | 1 hour |
| Agent client consolidation | ~200 lines | 2-3 hours |
| Consolidate app hooks | ~200 lines | 2-3 hours |
| Generic EntityPanel | ~400 lines | 1 day |
| UI package collapse | N/A (simplicity) | 1 day |
| **Total Estimated** | **~2000 lines** | **1-2 weeks** |
