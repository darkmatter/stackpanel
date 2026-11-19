# Demo agent (MSW prototype)

Studio demo mode (`/studio?demo=1`) uses an in-browser mock of the Go agent.
Module state lasts for the current page; reloading starts with the original fixtures.

## Files

| Path | Purpose |
|---|---|
| `fixture.ts` | Frozen demo data: `stack.json` shape, Nix config, entity tables. |
| `handlers.ts` | MSW handlers for HTTP requests in demo mode. |
| `connect-handlers.ts` | MSW adapter for project-scoped Connect procedures and simulated shell status. |
| `module-service.ts`, `module-fixtures.ts` | In-memory module lifecycle, versioned catalog and evaluated panel data. |
| `worker.ts` | Lazy `setupWorker(...)` + idempotent `startDemoWorker()`. |
| `token.ts` | Synthesises a non-expiring fake JWT (only decoded, never verified). |

## One-time bootstrap

MSW ships its own service-worker script that needs to live in `public/`:

```bash
cd apps/web
bunx msw init public/ --save
```

That command writes `public/mockServiceWorker.js`. Commit it; both dev and
production builds load it from the static path `/mockServiceWorker.js`.

## What's mocked today

- `GET /health`, `GET /api/auth/validate`
- `GET /api/events` → 204 (forces fall-back to polling, no SSE stream yet)
- `GET|POST /api/nix/config`, `GET|POST /api/nix/data?entity=*`
- `POST /api/exec` (no-op echo)
- `stackpanel.agent.v1.ModuleService`: list and read modules and outputs; browse, install, update and uninstall demo releases; preview, enable, configure and disable installed modules. Install alone does not enable a module. The `inspect` action streams the installed module's demo settings. There are no custom UI bundles.
- `stackpanel.agent.v1.ShellService`: module edits mark the demo shell stale. A simulated rebuild clears that state; it does not execute Nix.

Everything else falls through (`onUnhandledRequest: "bypass"`); add handlers
as you discover blank panels.
