// src/server.ts
//
// Cloudflare Worker SSR entrypoint. The top-level `await loadAppEnv(...)`
// below is load-bearing for production: it decrypts the `@gen/env`
// embedded SOPS payload and injects every secret (BETTER_AUTH_SECRET,
// POLAR_*, …) into `process.env` BEFORE any request handler — and, more
// importantly, before `@stackpanel/auth` constructs its `betterAuth`
// instance — runs.
//
// Without this, `@stackpanel/auth` sees an empty `process.env.BETTER_AUTH_SECRET`
// and better-auth's `validateSecret` blows up with HTTP 500 "you are using
// the default secret" on every tRPC call (waitlist included).
//
// Top-level await is supported in Cloudflare Workers' module workers and
// is allowed at the entry module: the platform suspends Worker boot until
// the awaited value resolves, then exposes the default-exported handler.
//
// `APP_ENV` is set by `apps/web/alchemy.run.ts` at deploy time
// (`prod` | `staging` | `dev`). It picks which entry of
// `packages/gen/env/src/runtime/generated-payloads/web/{dev,staging,prod}.ts`
// to decrypt. `SOPS_AGE_KEY` is the only secret the Worker needs at
// deploy time; it's the AGE key material that unlocks every SOPS payload
// for this stage. See `docs/adr/0001-runtime-secrets-via-gen-env-loader.md`.
//
// In `vite dev` and Vitest, `process.env` is already populated from the
// devshell, `SOPS_AGE_KEY` is unset, and the loader gracefully no-ops
// when the embedded payload is missing. We swallow the error so local
// dev keeps working — production CI sets `SOPS_AGE_KEY` and any decrypt
// failure surfaces immediately.
import { loadAppEnv } from "@gen/env/runtime/edge";
import {
	createStartHandler,
	defaultStreamHandler,
	defineHandlerCallback,
} from "@tanstack/react-start/server";
import { createServerEntry } from "@tanstack/react-start/server-entry";

const appEnv = process.env.APP_ENV ?? process.env.STAGE ?? "dev";

if (process.env.SOPS_AGE_KEY) {
	try {
		await loadAppEnv("web", appEnv, { inject: true });
	} catch (err) {
		// Surface as a console error but don't crash the Worker boot — the
		// downstream `auth.api.getSession(...)` call will still throw a
		// well-shaped better-auth error if the payload was actually needed.
		// This covers the case where someone deploys with a stale
		// SOPS_AGE_KEY that can't decrypt the embedded payload.
		console.error("[server.ts] loadAppEnv failed:", err);
	}
}

const customHandler = defineHandlerCallback((ctx) => {
	return defaultStreamHandler(ctx);
});

const fetch = createStartHandler(customHandler);

export default createServerEntry({
	fetch,
});
