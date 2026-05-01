import { checkout, polar, portal, webhooks } from "@polar-sh/better-auth";
import { Polar } from "@polar-sh/sdk";
import { db } from "@stackpanel/db";
import type { BetterAuthPlugin } from "better-auth";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { organization } from "better-auth/plugins";
import { polarProducts } from "./lib/polar-products";
import { polarSubscriptionCallbacks } from "./lib/polar-webhooks";

// ---------------------------------------------------------------------------
// Runtime env load (top-level await).
//
// In the Cloudflare-deployed `apps/web` Worker we ship the SOPS payload
// for this app+stage embedded in `@gen/env`. The payload contains
// BETTER_AUTH_SECRET, POLAR_*, etc. as ciphertext. The Worker boots with
// only `SOPS_AGE_KEY` (the AGE key material that unlocks the payload)
// and `APP_ENV` (the SOPS namespace discriminator) set as Worker env
// vars by `apps/web/alchemy.run.ts`. We use them here to decrypt the
// payload BEFORE `betterAuth({...})` is called below — otherwise
// better-auth's `validateSecret` blows up with HTTP 500 ("you are using
// the default secret") on every request that touches `auth.api`.
//
// On the Fly-deployed `apps/api` and during local dev / vitest, secrets
// are already in `process.env` (Fly secrets push, devshell SOPS load,
// or test fixtures), `SOPS_AGE_KEY` is unset, and the load is skipped.
//
// `inject: false` returns the decrypted record without mutating
// `process.env`. We pass the values directly to `betterAuth({...})` via
// the explicit `secret`/`POLAR_*` plumbing below to sidestep any
// edge-runtime read-only-process.env behaviour.
//
// See `docs/adr/0001-runtime-secrets-via-gen-env-loader.md`.
// ---------------------------------------------------------------------------

type RuntimeEnv = Record<string, string>;

async function loadRuntimeEnv(): Promise<RuntimeEnv> {
  if (typeof process === "undefined") return {};
  if (!process.env.SOPS_AGE_KEY) return {};
  try {
    const { loadAppEnv } = await import("@gen/env/runtime/edge");
    const appName = process.env.APP_NAME ?? "web";
    const appEnv = process.env.APP_ENV ?? process.env.STAGE ?? "dev";
    const payload = (await loadAppEnv(appName, appEnv, { inject: true })) as Record<string, string>;
    return payload;
  } catch (err) {
    console.error("[@stackpanel/auth] failed to load runtime env:", err);
    return {};
  }
}

const runtimeEnv: RuntimeEnv = await loadRuntimeEnv();

function envOf(key: string): string | undefined {
  const fromPayload = runtimeEnv[key];
  if (fromPayload !== undefined && fromPayload !== "") return fromPayload;
  if (typeof process !== "undefined") {
    const fromProcess = process.env[key];
    if (fromProcess !== undefined && fromProcess !== "") return fromProcess;
  }
  return undefined;
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

// Polar client is constructed AFTER `loadRuntimeEnv()` populates
// `process.env`, so `POLAR_ACCESS_TOKEN` reflects the SOPS-decrypted
// payload. If we imported a top-level `polarClient` const from
// `./lib/payments`, that const would evaluate before the TLA above and
// always resolve to `null` in the Worker — breaking checkout/portal.
const polarAccessToken = envOf("POLAR_ACCESS_TOKEN");
const polarClient = polarAccessToken
	? new Polar({
			accessToken: polarAccessToken,
			server: "sandbox",
		})
	: null;

if (polarClient) {
  const products = polarProducts();
  const polarUse: Parameters<typeof polar>[0]["use"] = [
    checkout({
      products: [
        { productId: products.pro, slug: "Pro" },
        { productId: products.free, slug: "Free" },
      ],
      successUrl: envOf("POLAR_SUCCESS_URL"),
      authenticatedUsersOnly: true,
    }),
    portal(),
  ];

  // Wire webhooks only when the secret is configured. Missing secret ->
  // skip webhook mount so the server still boots; subscription mirror
  // stays at whatever the DB says, and paid features refuse everyone.
  const polarWebhookSecret = envOf("POLAR_WEBHOOK_SECRET");
  if (polarWebhookSecret) {
    polarUse.push(
      webhooks({
        secret: polarWebhookSecret,
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
const deployEnv = envOf("STACKPANEL_DEPLOY_ENV");
const crossSubDomainCookies =
  deployEnv === "production"
    ? { enabled: true as const, domain: ".stackpanel.com" }
    : undefined;

const corsOrigin = envOf("CORS_ORIGIN");

export const auth = betterAuth({
  // `secret` is passed explicitly so we don't depend on better-auth
  // reading it back from `process.env` — some edge runtimes treat
  // `process.env` as read-only, which would silently break the
  // `inject: true` path of `loadAppEnv`.
  secret: envOf("BETTER_AUTH_SECRET"),
  database: drizzleAdapter(db, {
    provider: "pg",
  }),
  trustedOrigins: corsOrigin ? [corsOrigin] : [],
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
