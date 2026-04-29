# Demo agent (MSW prototype)

The `/demo` route mounts the studio against an in-browser mock of the Go agent
so visitors to stackpanel.com can poke at the UI without a real environment.

## Files

| Path | Purpose |
|---|---|
| `fixture.ts` | Frozen demo data: `stack.json` shape, Nix config, entity tables. |
| `handlers.ts` | MSW handlers for the agent REST surface + a Connect-RPC catch-all. |
| `worker.ts` | Lazy `setupWorker(...)` + idempotent `startDemoWorker()`. |
| `token.ts` | Synthesises a non-expiring fake JWT (only decoded, never verified). |
| `../routes/demo.tsx` | `/demo` route: boots the worker, mounts the studio. |

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
- `POST /<service>.<method>` Connect-RPC catch-all returning `{}`

Everything else falls through (`onUnhandledRequest: "bypass"`); add handlers
as you discover blank panels.

## Next step: proto-driven mocks

Long-term these handlers should be generated from `packages/proto/`. A buf
plugin can emit `handlers.gen.ts` — one MSW stub per RPC method, typed off
the same descriptors that drive the Go agent and the TS Connect client — and
this hand-written `handlers.ts` becomes overrides on top of the generated
defaults.
