# Complexity Reduction Analysis

A comprehensive analysis of complexity reduction opportunities across the stack codebase.

---

## Executive Summary

The codebase shows signs of organic growth with several patterns that add complexity without proportional value. The main areas of concern are:

1. **Agent client abstraction layers** - Multiple ways to create/use the agent client
2. **State management duplication** - Re-implementing React Query patterns manually
3. **Hook proliferation** - Many thin wrapper hooks that add indirection
4. **Nix module layering** - Proto → options → computed chain is complex
5. **UI package fragmentation** - 5 UI packages that could be 2

**Estimated total complexity reduction: 25-35% fewer lines of code, significantly easier to understand**

---

## 1. Unnecessary Abstractions

### 1.1 Multiple Agent Client Creation Patterns

**Location:** Throughout `apps/web/src/`

**What:** There are multiple ways to create and use the agent client:
- `createAgentClient(token)` helper function duplicated in 4+ files
- `new AgentHttpClient("localhost", 9876, token)` scattered everywhere
- `new AgentHttpClient({ token })` (config object style)
- `useAgentContext()` → context value
- `useAgent()` hook
- `NixClient` wrapper around `AgentHttpClient`

**Evidence:**
- [setup-wizard.tsx#L46-L47](apps/web/src/components/studio/panels/setup/setup-wizard.tsx#L46-L47) - local `createAgentClient`
- [edit-secret-dialog.tsx#L35-L36](apps/web/src/components/studio/panels/variables/edit-secret-dialog.tsx#L35-L36) - same helper duplicated
- [add-variable-dialog.tsx#L89](apps/web/src/components/studio/panels/variables/add-variable-dialog.tsx#L89) - direct instantiation

**Why Problematic:**
- Can't easily change host/port configuration
- Hard-coded "localhost:9876" in multiple places
- Duplicated error handling patterns
- No centralized retry/token refresh logic

**Simplification Strategy:**
```typescript
// Create single useAgentClient hook that returns a cached client
function useAgentClient() {
  const { token, host, port } = useAgentContext();
  return useMemo(() => new AgentHttpClient({ host, port, token }), [host, port, token]);
}

// Components just use:
const client = useAgentClient();
```

**Impact:** HIGH - Reduces 200+ lines of duplicated code, centralizes configuration

---

### 1.2 AgentClient vs AgentHttpClient vs NixClient

**Location:** `apps/web/src/lib/agent.ts`, `apps/web/src/lib/nix-client.ts`

**What:** Three client classes that overlap:
- `AgentClient` - WebSocket-based, 200+ lines, barely used
- `AgentHttpClient` - HTTP-based, 500+ lines, actively used
- `NixClient` - Wraps AgentHttpClient with snake_case/kebab-case transforms

**Why Problematic:**
- WebSocket client is dead code (SSE is used instead)
- NixClient adds a layer that just transforms keys
- 1140 lines in agent.ts, most for rarely-used WebSocket code

**Simplification Strategy:**
1. Delete `AgentClient` class entirely (WebSocket is not used)
2. Move key transformation into `AgentHttpClient`
3. Export typed methods directly from `AgentHttpClient`

**Impact:** HIGH - Eliminates ~400 lines, removes dead code

---

### 1.3 Over-engineered Key Transformation

**Location:** `apps/web/src/lib/nix-client.ts`, `apps/web/src/lib/nix-data/`

**What:** Complex runtime snake_case ↔ kebab-case transformation for every API call.

**Why Problematic:**
- Nix files use kebab-case, TypeScript uses snake_case
- Every read/write does recursive transformation
- Error-prone, hard to debug

**Simplification Strategy:**
- Use kebab-case in TypeScript types too (matches source of truth)
- Or: Generate types from proto with both case options at build time
- Remove runtime transformation entirely

**Impact:** MEDIUM - Removes ~150 lines, eliminates a class of bugs

---

## 2. State Management Complexity

### 2.1 Custom React Query Re-implementation

**Location:** `apps/web/src/lib/use-nix-config.ts` (959 lines)

**What:** Hand-rolled query state management that reimplements React Query:
```typescript
interface QueryState<T> {
  data: T | null;
  error: Error | null;
  status: QueryStatus;
  isLoading: boolean;
  isError: boolean;
  isSuccess: boolean;
  dataUpdatedAt: number | null;
}
```

Each hook manually:
- Manages loading/error/success states
- Implements refetch callbacks
- Handles SSE event subscriptions
- Duplicates the same patterns 15+ times

**Evidence:** The file has 6+ `useEffect` calls, 10+ `useCallback` calls, each hook ~80-100 lines

**Why Problematic:**
- No caching between components
- No automatic deduplication
- No background refetching
- Massive code duplication

**Simplification Strategy:**
Replace with TanStack Query:
```typescript
// Before: 80 lines
export function useApps() {
  const client = useNixClient();
  const [state, setState] = useState(...);
  const fetchData = useCallback(...);
  useEffect(...);
  useAgentSSEEvent(...);
  return { ...state, refetch };
}

// After: 10 lines
export function useApps() {
  const client = useNixClient();
  return useQuery({
    queryKey: ['apps'],
    queryFn: () => client.entity('apps').get(),
  });
}
```

**Impact:** HIGH - Reduces use-nix-config.ts from 959 to ~200 lines, adds caching

---

### 2.2 Prop Drilling in Setup Wizard

**Location:** `apps/web/src/components/studio/panels/setup/setup-wizard.tsx`

**What:** 1339-line component that:
- Maintains 15+ pieces of state
- Passes 10+ props to step components
- Re-creates handler functions on every render

**Evidence:**
```typescript
const [projectInfo, setProjectInfo] = useState<Project | null>(null);
const [projectConfirmed, setProjectConfirmed] = useState(false);
const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(null);
const [kmsConfig, setKmsConfig] = useState<KMSConfigResponse | null>(null);
const [usersConfigured, setUsersConfigured] = useState(false);
const [sopsConfigGenerated, setSopsConfigGenerated] = useState(false);
const [identityInput, setIdentityInput] = useState("");
const [isSaving, setIsSaving] = useState(false);
const [isGeneratingSops, setIsGeneratingSops] = useState(false);
// ... and more
```

**Why Problematic:**
- Any change to state management requires touching this giant file
- Steps can't be lazy-loaded
- Testing is difficult

**Simplification Strategy:**
1. Create `SetupWizardContext` with all state (already partially done)
2. Move step-specific state INTO step components
3. Use a reducer for wizard state machine
4. Each step manages its own loading/saving states

**Impact:** HIGH - Could reduce main file to 200 lines, enables code splitting

---

### 2.3 Derived State Not Used

**Location:** Multiple panel components

**What:** State that could be derived is stored separately:
```typescript
const [resolvedApps, setResolvedApps] = useState(...);
// Instead of:
const resolvedApps = useMemo(() => apps ? addIds(apps) : null, [apps]);
```

**Evidence:** `useResolvedApps` in use-nix-config.ts wraps `useApps` just to add `id` field

**Simplification Strategy:**
- Add `id` to apps during fetch, not in a wrapper hook
- Remove `useResolvedApps` hook entirely
- Use `useMemo` for transforms in components

**Impact:** LOW - Removes ~50 lines, simplifies mental model

---

## 3. Duplicate Concepts

### 3.1 Multiple Ways to Manage Apps

**Location:** `apps/web/src/lib/use-nix-config.ts`

**What:** Overlapping hooks for the same data:
- `useApps()` - raw apps
- `useResolvedApps()` - apps with id field
- `useApp(id)` - single app
- `useAppsWithTask(taskName)` - filtered apps
- `useAppsWithVariable(varName)` - filtered apps
- `useAllAppTasks()` - flattened tasks
- `useAllAppVariables()` - flattened variables

**Why Problematic:**
- 7 hooks for essentially one data source
- Each makes its own fetch
- No shared cache

**Simplification Strategy:**
Single hook with selectors:
```typescript
const { apps } = useApps();
const webApp = apps?.['web'];  // Direct access
const appsWithBuild = useMemo(() =>
  filterAppsWithTask(apps, 'build'), [apps]);
```

**Impact:** MEDIUM - Removes 5 hooks (~200 lines)

---

### 3.2 UI Package Fragmentation -- RESOLVED

**Location:** `packages/ui/`

**What was done:** 5 UI packages consolidated to 2:
- Deleted `@stack/ui` facade (unused indirection)
- Deleted `@stack/ui-primitives` (merged 27 `@radix-ui/*` deps into `ui-web`)
- Deleted `@stack/ui-native` (empty stub, zero components)
- Kept `@stack/ui-core` (cn, cva, Logo, CSS) at `packages/ui/core/`
- Kept `@stack/ui-web` (16 shadcn components) at `packages/ui/web/`
- Updated 11 imports in `ui-web` from `@stack/ui-primitives` to direct `@radix-ui/*`

**Impact:** 5 packages down to 2, cleaner dependency graph, no facade indirection

---

### 3.3 Similar Panel Components

**Location:** `apps/web/src/components/studio/panels/`

**What:** Panel components with similar structure but different implementations:
- `apps-panel-alt.tsx` (558 lines)
- `services-panel.tsx` (307 lines)
- `packages-panel.tsx` (688 lines)
- `variables-panel.tsx` (359 lines)

Each has: list view, detail view, add/edit dialogs, loading states

**Simplification Strategy:**
Create generic `EntityPanel` component:
```tsx
<EntityPanel
  entity="apps"
  renderItem={(app) => <AppCard app={app} />}
  renderDetail={(app) => <AppDetail app={app} />}
  emptyState={<AddAppCTA />}
/>
```

**Impact:** MEDIUM - Could consolidate ~400 lines of shared patterns

---

## 4. Nix Module Complexity

### 4.1 Proto → Options → Computed Chain

**Location:** `nix/stack/db/`, `nix/stack/core/options/`

**What:** Three-layer system:
1. `.proto.nix` files define schema
2. `options.nix` converts proto to Nix options
3. `*Computed` attributes derive values

The chain: proto → mkOptionsFromMessage → options → computed values

**Why Problematic:**
- Hard to understand what options are available
- Debug cycle is slow
- Proto schema is overkill for most options

**Simplification Strategy:**
For simple modules, skip proto entirely:
```nix
# Instead of defining in .proto.nix and generating options:
options.stack.name = lib.mkOption {
  type = lib.types.str;
  default = "my-project";
};
```

Reserve proto for types that need TypeScript/Go codegen.

**Impact:** MEDIUM - Simplifies adding new options

---

### 4.2 Overly-Parameterized SST Module

**Location:** `nix/stack/sst/sst.nix` (684 lines)

**What:** Massive configuration surface:
- Multiple OIDC providers (GitHub, Fly.io, Roles Anywhere)
- KMS key configuration
- IAM role configuration
- Complex string interpolation for TypeScript generation

**Why Problematic:**
- Most users only need GitHub Actions OIDC
- Fly.io and Roles Anywhere rarely used
- Generates TypeScript via string interpolation (fragile)

**Simplification Strategy:**
1. Default to GitHub Actions OIDC only
2. Move other providers to extension modules
3. Generate sst.config.ts from a template file, not string concat

**Impact:** MEDIUM - Could reduce to 300 lines

---

### 4.3 Ports Library Over-Engineering

**Location:** `nix/stack/lib/ports.nix` (216 lines)

**What:** Complex deterministic port assignment:
- Hash-based port computation
- Service offset calculation
- Multiple ways to compute ports

**Why Problematic:**
- Most projects just want static port numbers
- Hash algorithm is hard to understand
- Rarely provides value over explicit ports

**Simplification Strategy:**
```nix
# Instead of complex computation:
stack.apps.web.port = 3000;
stack.apps.api.port = 3001;

# Auto-assign only if not specified:
port = config.stack.apps.${name}.port or (3000 + offset);
```

**Impact:** LOW - Simplifies for new users

---

## 5. API Surface Reduction

### 5.1 Too Many Exported Hooks

**Location:** `apps/web/src/lib/use-nix-config.ts`

**What:** 19+ exported hooks/functions:
- useNixConfig, useNixData, useNixMapData
- useResolvedApps, useServices, useTasks, useVariables
- useApps, useApp, useAppsWithTask, useAppsWithVariable
- useAllAppTasks, useAllAppVariables
- useUpdateApp, useDeleteApp
- useTurboPackages, useTurboTasks
- Plus type re-exports

**Why Problematic:**
- Hard to know which hook to use
- Many are rarely used
- Maintenance burden

**Simplification Strategy:**
Reduce to core hooks only:
```typescript
export { useNixConfig }     // Full config
export { useNixData }       // Single entity
export { useNixMapData }    // Map entity (apps, services, etc.)
export { useTurboPackages } // Turbo integration
```

Derived hooks can be inline utilities or removed.

**Impact:** MEDIUM - Simplifies API, reduces docs burden

---

### 5.2 Agent.ts Type Exports

**Location:** `apps/web/src/lib/agent.ts`

**What:** 50+ exported types/interfaces for every API shape

**Why Problematic:**
- Most types only used in one place
- Could be inferred from function returns
- Duplicates types from proto

**Simplification Strategy:**
- Import types from `@stack/proto` where possible
- Keep only types needed for public API
- Use `ReturnType<typeof client.method>` for internal types

**Impact:** LOW - Reduces type maintenance

---

## 6. Build/Dev Workflow Simplification

### 6.1 Generated Files Complexity

**Location:** `nix/stack/modules/turbo.nix`

**What:** Complex system to:
1. Generate turbo.json from Nix
2. Create task scripts as Nix derivations
3. Symlink scripts to .tasks/bin/
4. Generate package.json script entries

**Why Problematic:**
- Debugging task scripts is hard (they're in /nix/store)
- turbo.json regenerated on every nix eval
- Complex symlink management

**Simplification Strategy:**
- Keep turbo.json static, edit directly
- Use npm scripts directly instead of Nix-wrapped scripts
- Only use Nix wrappers for complex tasks with dependencies

**Impact:** MEDIUM - Faster dev loop, easier debugging

---

### 6.2 Proto Codegen Complexity

**Location:** `nix/stack/db/`

**What:** System to:
1. Define types in .proto.nix
2. Render to .proto files
3. Run buf generate
4. Import in TypeScript/Go

**Why Problematic:**
- Proto is overkill for internal types
- Adds build step
- Types drift from Nix options

**Simplification Strategy:**
- Use proto only for Go ↔ TypeScript communication
- Define Nix options directly, not via proto
- Consider TypeBox or Zod for runtime validation

**Impact:** MEDIUM - Simpler for adding new types

---

## Priority Matrix

| Category | Finding | Impact | Effort | Priority |
|----------|---------|--------|--------|----------|
| Abstractions | Agent client unification | HIGH | LOW | P0 |
| State Mgmt | Replace with React Query | HIGH | MEDIUM | P0 |
| Abstractions | Delete WebSocket client | HIGH | LOW | P1 |
| State Mgmt | Setup wizard reducer | HIGH | MEDIUM | P1 |
| Duplicates | Consolidate app hooks | MEDIUM | LOW | P1 |
| UI | ~~Collapse UI packages~~ | ~~MEDIUM~~ | ~~MEDIUM~~ | DONE |
| Nix | Simplify SST module | MEDIUM | MEDIUM | P2 |
| API | Reduce exported hooks | MEDIUM | LOW | P2 |
| Nix | Skip proto for simple opts | MEDIUM | HIGH | P3 |
| Build | Static turbo.json | MEDIUM | MEDIUM | P3 |

---

## Quick Wins (< 1 hour each)

1. **Delete AgentClient (WebSocket)** - Remove ~200 lines of dead code
2. **Unify createAgentClient** - Replace 4 local helpers with one export
3. **Remove useResolvedApps** - Inline the ID addition in useApps
4. **Delete unused hooks** - useAppsWithTask, useAppsWithVariable rarely used
5. **Consolidate key transforms** - Move to single place

---

## Recommended Action Plan

### Phase 1: Agent Client Cleanup (1-2 days)
1. Delete `AgentClient` class
2. Create `useAgentClient()` hook
3. Update all files using `createAgentClient` or `new AgentHttpClient`
4. Remove duplicated helper functions

### Phase 2: State Management (2-3 days)
1. Add TanStack Query
2. Migrate `useNixConfig` to use Query
3. Migrate `useNixData` to use Query
4. Update SSE integration to use Query's cache invalidation

### Phase 3: Hook Consolidation (1 day)
1. Remove thin wrapper hooks
2. Export selectors/utilities instead
3. Update imports in consumers

### Phase 4: Nix Simplification (2-3 days)
1. Simplify SST module (GitHub Actions only by default)
2. Make ports explicit by default
3. Document the proto workflow better

---

## Metrics to Track

- **Lines of code** - Target 25% reduction in apps/web/src/lib/
- **Import depth** - No more than 2 levels to get agent client
- **Hook count** - Reduce from 19 to ~8 exported hooks
- **Build time** - Nix eval should be under 5s
- **Bundle size** - Remove dead WebSocket code

