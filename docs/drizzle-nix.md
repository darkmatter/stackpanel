# Plan: Drizzle-like DX for Nix-as-Database

Create a typed client layer that gives Drizzle-like ergonomics for querying/mutating Nix config from web clients, with SSE-driven reactivity and type generation from Nix option definitions. Mutations write Nix data files directly to `.stack/data/`, eliminating cache staleness.

## Steps

1. **Generate JSON Schema from Nix options** – Extend `nix/stack/core/state.nix` to export a `schema.json` alongside `stack.json`, derived from `lib.mkOption` types/descriptions, similar to the existing pattern in `nix/stack/secrets/`.

2. **Generate TypeScript types from JSON Schema** – Add a codegen step using `quicktype` (already used in `nix/stack/secrets/codegen.nix`) to produce typed interfaces in `packages/api/src/generated/`, invalidated when schema changes.

3. **Create a typed `NixClient` class** – In `packages/api/src/nix-client.ts`, implement a client wrapping `/api/nix/eval` with methods like `client.apps.get("web")` and `client.secrets.list()`, using generated types for full inference.

4. **Add SSE-backed reactive store** – Create a `useNixConfig()` hook in `apps/web/src/lib/` that subscribes to `config.changed` via `useAgentSSEEvent` and maintains a typed client-side cache, similar to TanStack Query's pattern.

5. **Write Nix data files for mutations** – Mutations serialize to Nix expressions and write to `$STACKPANEL_ROOT/.stack/data/<entity>.nix` via the agent's `/api/files` endpoint; each "table" is a separate file (e.g., `apps.nix`, `secrets.nix`), checked into git, and re-evaluated on next read.

6. **Add Nix serializer utility** – Create a Go helper in `packages/stack-go/` (or agent) that converts typed structs to valid Nix syntax (attrsets, lists, strings with proper escaping), used by mutation endpoints.

## Considerations

1. **Nix-first with UI abstraction** – Confirmed: Nix remains source-of-truth; devs interact via agent/web UI only, never touching Nix directly.

2. **File-per-entity mutations** – Confirmed: Each mutation writes an entire `.nix` file in `.stack/data/`; no partial updates, keeping logic simple and diffs readable.

3. **Client-side caching** – Confirmed: Cache lives in React state/context; SSE `config.changed` events trigger re-fetch from agent, no server-side query cache needed.
