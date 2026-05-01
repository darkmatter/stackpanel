import { checkout, polar, portal, webhooks } from "@polar-sh/better-auth";
import { db, runMigrations } from "@stackpanel/db";
import type { BetterAuthPlugin } from "better-auth";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { organization } from "better-auth/plugins";
import { polarClient } from "./lib/payments";
import { polarProducts } from "./lib/polar-products";
import { polarSubscriptionCallbacks } from "./lib/polar-webhooks";

// Apply file-based Drizzle migrations from `@stackpanel/db` before any
// auth-bound query runs. We do this at module-evaluation time (top-level
// await) so the per-isolate boot order is always:
//   1. import @stackpanel/db   → drizzle client + bundled migrations available
//   2. await runMigrations(db) → __drizzle_migrations is up-to-date
//   3. betterAuth({...})       → drizzle adapter is safe to construct & query
// See `docs/adr/0002-runtime-startup-migrations.md` for the full rationale.
//
// `runMigrations` is internally cached + serialized via `pg_advisory_lock`,
// so concurrent isolates cooperate. We guard on a configured connection
// string so vitest/typecheck contexts (which never set DATABASE_URL) don't
// crash at import time on a connection refused error.
if (process.env.DATABASE_URL || process.env.POSTGRES_URL) {
  await runMigrations(db);
}

// Build plugins array - only include Polar if configured
const plugins: BetterAuthPlugin[] = [
	organization({
		// A user's first login auto-creates a personal organization so every
		// session has an active organization. Paid features are scoped to the
		// active organization, not the user.
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

  // Wire webhooks only when the secret is configured. Missing secret ->
  // skip webhook mount so the server still boots; subscription mirror
  // stays at whatever the DB says, and paid features refuse everyone.
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

// In production both stackpanel.com and local.stackpanel.com serve the same
// app, and the API at api.stackpanel.com sets the session cookie. Scoping
// the cookie to `.stackpanel.com` lets a sign-in from the apex carry into
// the studio subdomain. Outside production we leave it host-only — preview
// stages live on per-PR subdomains that share nothing with each other, and
// local dev runs on localhost where a domain attribute would be ignored.
const deployEnv = process.env.STACKPANEL_DEPLOY_ENV;
const crossSubDomainCookies =
  deployEnv === "production"
    ? { enabled: true as const, domain: ".stackpanel.com" }
    : undefined;

export const auth = betterAuth({
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

export type Auth = typeof auth;
export type Session = (typeof auth)["$Infer"]["Session"];
