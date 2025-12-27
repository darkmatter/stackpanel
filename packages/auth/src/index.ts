import { checkout, polar, portal } from "@polar-sh/better-auth";
import { db } from "@stackpanel/db";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { polarClient } from "./lib/payments";

export const auth = betterAuth({
	database: drizzleAdapter(db, {
		provider: "pg",
	}),
	trustedOrigins: [process.env.CORS_ORIGIN || ""],
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
	plugins: [
		polar({
			client: polarClient,
			createCustomerOnSignUp: true,
			enableCustomerPortal: true,
			use: [
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
			],
		}) as unknown as import("better-auth").BetterAuthPlugin,
	],
});

export type Auth = typeof auth;
export type Session = (typeof auth)["$Infer"]["Session"];
