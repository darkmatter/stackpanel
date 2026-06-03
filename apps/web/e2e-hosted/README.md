# Hosted E2E (production / staging)

Browser-driven tests that exercise a **deployed** StackPanel studio (prod or
staging), as opposed to `apps/web/e2e/` which spins up a local web server + a
local `go run . agent` and drives them together.

This split exists because the production architecture is
`hosted web ↔ local agent ↔ local repo`: the studio is served from
`stackpanel.com`, pairs with an agent running on `localhost:9876`, and that
agent manages a real project on disk.

## Prerequisites

```bash
bun install                      # workspace deps (incl. @playwright/test)
bunx playwright install chromium # browser binary
```

> In a bare container without Nix you can still run everything here: the agent
> side uses plain `go run` (see the studio spec), no devshell required.

## Read-only smoke (safe against any environment)

`*.smoke.spec.ts` only loads public pages and asserts the app renders + gates
auth correctly. **No login, no signup, no writes** — safe to point at prod.

```bash
# staging (preferred once healthy)
SMOKE_BASE_URL=https://staging.stackpanel.com \
  bunx playwright test --config apps/web/e2e-hosted/playwright.hosted.config.ts

# production (default)
bunx playwright test --config apps/web/e2e-hosted/playwright.hosted.config.ts
```

What it checks:

- `/` renders with no uncaught page errors (catches white-screen / JS-crash regressions)
- `/dashboard` redirects an unauthenticated visitor to `/login`
- `/login` presents a sign-in affordance (client-rendered form)
- `/studio` responds without a 5xx and without uncaught errors

## Full studio ↔ agent E2E (authenticated) — `*.studio.spec.ts`

Drives the real happy path: log in, pair the hosted studio to a **local** agent
serving `examples/multi-app`, and verify apps/services/ports/secrets render from
the live agent. Requires:

| Env var | Purpose |
| --- | --- |
| `SMOKE_BASE_URL` | Hosted studio to drive (use **staging**, not prod) |
| `STUDIO_TEST_EMAIL` / `STUDIO_TEST_PASSWORD` | Dedicated test account on that env |
| `STACKPANEL_AGENT_PORT` | Local agent port (default 9876) |
| `STACKPANEL_TEST_PAIRING_TOKEN` | Pre-shared pairing token so the agent auto-pairs |

The spec boots the agent with:

```bash
( cd apps/stackpanel-go && \
  STACKPANEL_TEST_PAIRING_TOKEN=$TOKEN \
  go run . agent --port $STACKPANEL_AGENT_PORT --project-root ../../examples/multi-app )
```

> **Status:** authored against `staging.stackpanel.com`. As of this writing
> staging is returning no response (web) / 503 (api), so this spec is skipped
> unless `SMOKE_BASE_URL` resolves AND the test-account env vars are set. Run it
> once staging is back up, or against a dedicated test account on prod with
> explicit sign-off.
