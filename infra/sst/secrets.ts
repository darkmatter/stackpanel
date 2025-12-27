/// <reference path="../../.sst/platform/config.d.ts" />

/**
 * SST Secrets
 *
 * All secrets used by the application.
 * Set via: bunx sst secret set SecretName value
 */

export function createSecrets() {
	return {
		// Database
		databaseUrl: new sst.Secret("DatabaseUrl"),

		// Redis/Cache
		redisUrl: new sst.Secret("RedisUrl"),
		redisToken: new sst.Secret("RedisToken"),

		// Authentication
		betterAuthSecret: new sst.Secret("BetterAuthSecret"),

		// Third-party APIs
		polarAccessToken: new sst.Secret("PolarAccessToken"),
		googleAiKey: new sst.Secret("GoogleAiKey"),
	};
}

export type Secrets = ReturnType<typeof createSecrets>;
