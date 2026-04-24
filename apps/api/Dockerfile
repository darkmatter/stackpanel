# syntax=docker/dockerfile:1.7-labs
#
# stackpanel-api container for Fly.
#
# Bun workspaces = install from monorepo root with the full repo present,
# then `cd apps/api && bun run`. We don't precompile because bun runs TS
# directly and the build surface is small. Multi-stage to drop source
# we don't need at runtime (state templates, sops artifacts, go code).

FROM oven/bun:1.3.2-alpine AS builder
WORKDIR /repo

# Copy the workspace files needed for `bun install`. Ideally we'd scope to
# just the API-adjacent packages but bun's frozen-lockfile installer wants
# the whole set up front — it's fast and deterministic.
COPY package.json bun.lock ./
COPY apps/api/package.json apps/api/
COPY packages/api/package.json packages/api/
COPY packages/auth/package.json packages/auth/
COPY packages/db/package.json packages/db/
COPY packages/gen/env/package.json packages/gen/env/
COPY packages/gen/config/package.json packages/gen/config/
COPY packages/config/package.json packages/config/

RUN bun install --frozen-lockfile --production

# Now copy source. Cache-friendly: deps install is frozen above, source
# churn doesn't re-trigger `bun install`.
COPY apps/api apps/api/
COPY packages/api packages/api/
COPY packages/auth packages/auth/
COPY packages/db packages/db/
COPY packages/gen packages/gen/
COPY packages/config packages/config/

FROM oven/bun:1.3.2-alpine AS runner
WORKDIR /repo

# Runtime user: non-root.
RUN addgroup -S api && adduser -S api -G api

COPY --from=builder --chown=api:api /repo /repo

USER api
WORKDIR /repo/apps/api

# Bun binds via fetch-api; PORT is injected by Fly.
ENV NODE_ENV=production
EXPOSE 3000

CMD ["bun", "run", "src/index.ts"]
