/// <reference path="../../.sst/platform/config.d.ts" />

/**
 * SST Configuration
 *
 * Centralized configuration for domains, environments, and settings.
 */

export const config = {
	name: "stackpanel",

	domains: {
		web: "stackpanel.com",
		docs: "docs.stackpanel.com",
	},

	// Local development URLs
	localUrls: {
		web: "http://localhost:3001",
		docs: "http://localhost:4000",
	},
} as const;

/**
 * Get environment variables for a given stage
 */
export function getEnvironment(isProd: boolean) {
	const baseUrl = isProd
		? `https://${config.domains.web}`
		: config.localUrls.web;

	return {
		CORS_ORIGIN: baseUrl,
		BETTER_AUTH_URL: baseUrl,
		POLAR_SUCCESS_URL: `${baseUrl}/success?checkout_id={CHECKOUT_ID}`,
	};
}

/**
 * Get domain for a resource, or undefined in non-prod
 */
export function getDomain(
	key: keyof typeof config.domains,
	isProd: boolean,
): string | undefined {
	return isProd ? config.domains[key] : undefined;
}
