import { checkout, polar, portal, webhooks } from "@polar-sh/better-auth";
import { db } from "@stackpanel/db";
import type { BetterAuthPlugin } from "better-auth";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { organization } from "better-auth/plugins";
import { polarClient } from "./lib/payments";
import { polarProducts } from "./lib/polar-products";
import { polarSubscriptionCallbacks } from "./lib/polar-webhooks";

// ---------------------------------------------------------------------------
// Lazy `betterAuth({...})` construction.
//
// The instance is built on first property access of the exported `auth`
// Proxy below — NOT at module load time. This matters for the Cloudflare
// Worker runtime in `apps/web`, where `process.env.BETTER_AUTH_SECRET` is
// populated at request time by an `await loadAppEnv("web", APP_ENV, {
// inject: true })` call in the SSR entrypoint. If we constructed the
// instance eagerly here, better-auth would call `validateSecret` against
// an empty `process.env.BETTER_AUTH_SECRET` during the import chain
// (routeTree.gen.ts → routes/api/trpc.$.ts → @stackpanel/auth) and crash
// every request with HTTP 500 ("you are using the default secret").
//
// On the Fly-deployed `apps/api` and during `bun run dev`, the secrets are
// already in `process.env` before the first import, so the Proxy's first
// access still sees a fully-populated env. The only behaviour change is
// the postponement of the `betterAuth({...})` call itself — see the ADR
// at `docs/adr/0001-runtime-secrets-via-gen-env-loader.md`.
// ---------------------------------------------------------------------------

function buildAuth() {
	const plugins: BetterAuthPlugin[] = [
		organization({
			// A user's first login auto-creates a personal organization so
			// every session has an active organization. Paid features are
			// scoped to the active organization, not the user.
			allowUserToCreateOrganization: true,
			organizationLimit: 10,
		}),
	];

	if (polarClient) {
		const products = polarProducts();
		const polarUse: Parameters<typeof polar>[0]["use"] = [
			checkout({
				products: [
					{ productId: products.pro, slug: "Pro" },
					{ productId: products.free, slug: "Free" },
				],
				successUrl: process.env.POLAR_SUCCESS_URL,
				authenticatedUsersOnly: true,
			}),
			portal(),
		];

		// Wire webhooks only when the secret is configured. Missing secret
		// → skip webhook mount so the server still boots; subscription
		// mirror stays at whatever the DB says, and paid features refuse
		// everyone.
		if (process.env.POLAR_WEBHOOK_SECRET) {
			polarUse.push(
				webhooks({
					secret: process.env.POLAR_WEBHOOK_SECRET,
					...polarSubscriptionCallbacks(),
				}),
			);
		}

		plugins.push(
			polar({
				client: polarClient,
				createCustomerOnSignUp: true,
				enableCustomerPortal: true,
				use: polarUse,
			}) as unknown as BetterAuthPlugin,
		);
	}

	// In production both stackpanel.com and local.stackpanel.com serve the
	// same app, and the API at api.stackpanel.com sets the session cookie.
	// Scoping the cookie to `.stackpanel.com` lets a sign-in from the apex
	// carry into the studio subdomain. Outside production we leave it
	// host-only — preview stages live on per-PR subdomains that share
	// nothing with each other, and local dev runs on localhost where a
	// domain attribute would be ignored.
	const deployEnv = process.env.STACKPANEL_DEPLOY_ENV;
	const crossSubDomainCookies =
		deployEnv === "production"
			? { enabled: true as const, domain: ".stackpanel.com" }
			: undefined;

	return betterAuth({
		database: drizzleAdapter(db, {
			provider: "pg",
		}),
		trustedOrigins: process.env.CORS_ORIGIN ? [process.env.CORS_ORIGIN] : [],
		emailAndPassword: {
			enabled: true,
		},
		advanced: {
			defaultCookieAttributes: {
				sameSite: "none",
				secure: true,
				httpOnly: true,
			},
			...(crossSubDomainCookies ? { crossSubDomainCookies } : {}),
		},
		plugins,
	});
}

type AuthInstance = ReturnType<typeof buildAuth>;

let cachedAuth: AuthInstance | null = null;
function ensureAuth(): AuthInstance {
	if (!cachedAuth) cachedAuth = buildAuth();
	return cachedAuth;
}

/**
 * Force-construct the `betterAuth({...})` instance now (and cache it).
 * Useful for tests and for entrypoints that want to surface init errors
 * immediately rather than on the first request.
 */
export function getAuth(): AuthInstance {
	return ensureAuth();
}

/**
 * Lazy `betterAuth({...})` instance, exposed as a Proxy so existing
 * callers that do `import { auth } from "@stackpanel/auth"; await
 * auth.api.getSession(...)` keep working unchanged. The first property
 * read on `auth` triggers `ensureAuth()`, which calls `buildAuth()` once
 * and memoises the result. See the comment block above for why this is
 * lazy.
 */
export const auth = new Proxy({} as AuthInstance, {
	get(_target, prop, receiver) {
		return Reflect.get(ensureAuth() as object, prop, receiver);
	},
	has(_target, prop) {
		return Reflect.has(ensureAuth() as object, prop);
	},
	ownKeys(_target) {
		return Reflect.ownKeys(ensureAuth() as object);
	},
	getOwnPropertyDescriptor(_target, prop) {
		return Reflect.getOwnPropertyDescriptor(ensureAuth() as object, prop);
	},
}) as AuthInstance;

export type Auth = AuthInstance;
export type Session = AuthInstance["$Infer"]["Session"];
