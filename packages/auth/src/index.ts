import { checkout, polar, portal, webhooks } from "@polar-sh/better-auth";
import { db } from "@stackpanel/db";
import type { BetterAuthPlugin } from "better-auth";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { organization } from "better-auth/plugins";
import { polarClient } from "./lib/payments";
import { polarSubscriptionCallbacks } from "./lib/polar-webhooks";

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
  const polarUse: Parameters<typeof polar>[0]["use"] = [
    checkout({
      products: [
        {
          productId: "5fb4014e-d879-4b28-966a-9efcf60b6c24",
          slug: "Pro",
        },
        {
          productId: "70acf138-0b13-4fd0-8c25-78c63f09a122",
          slug: "Free",
        },
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
  },
  plugins,
});

export type Auth = typeof auth;
export type Session = (typeof auth)["$Infer"]["Session"];
