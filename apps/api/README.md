# @stackpanel/api-server

Cloud API for stackpanel — Better-Auth, Polar webhooks, and paid tRPC
procedures (hosted alchemy state, future marketplace). Runs on Fly as a
Node/Bun service at `api.stackpanel.com`.

## Why this lives separately from apps/web

`apps/web` targets Cloudflare Workers (V8 isolates). Paid procedures use
`node:crypto` for AES-GCM envelope encryption and `@aws-sdk/client-kms`
for master-key operations — neither works on Workers. Rather than hack
around the runtime, paid endpoints live here in a real Node/Bun runtime.

## Dev

```sh
bun run dev
# listens on :3000
```

## Deploy

Runs from the monorepo root so Docker build context includes workspace
packages:

```sh
# First time only:
fly launch --config apps/api/fly.toml --dockerfile apps/api/Dockerfile --no-deploy
fly certs add api.stackpanel.com --app stackpanel-api

# Required secrets (set once, shared across deploys):
fly secrets set \
  DATABASE_URL='postgres://...' \
  BETTER_AUTH_URL='https://api.stackpanel.com' \
  BETTER_AUTH_SECRET='...' \
  CORS_ORIGIN='https://local.stackpanel.com' \
  CORS_ALLOWED_ORIGINS='https://local.stackpanel.com,https://stackpanel.com' \
  POLAR_ACCESS_TOKEN='polar_pat_...' \
  POLAR_WEBHOOK_SECRET='whsec_...' \
  POLAR_SUCCESS_URL='https://local.stackpanel.com/checkout/success' \
  AWS_ACCESS_KEY_ID='AKIA...' \
  AWS_SECRET_ACCESS_KEY='...' \
  AWS_REGION='us-east-1' \
  STACKPANEL_KMS_ALIAS='alias/stackpanel-secrets' \
  --app stackpanel-api

# Deploy:
fly deploy --config apps/api/fly.toml --dockerfile apps/api/Dockerfile --app stackpanel-api
```

## Endpoints

- `GET /` — service info
- `GET /health` — health check (used by Fly)
- `GET|POST /api/auth/*` — Better-Auth (sign-in, sign-up, session,
  Polar checkout/portal, `/api/auth/polar/webhooks`)
- `ALL /trpc/*` — tRPC router (`agent`, `alchemyState`, `github`)
