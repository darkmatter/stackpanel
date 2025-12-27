/// <reference path="./.sst/platform/config.d.ts" />

export default $config({
	app(input) {
		return {
			name: "stackpanel",
			removal: input?.stage === "prod" ? "retain" : "remove",
			protect: ["prod"].includes(input?.stage),
			home: "cloudflare",
		};
	},
	async run() {
		// ========================================================================
		// Secrets (set via: bunx sst secret set SecretName value)
		// ========================================================================
		const databaseUrl = new sst.Secret("DatabaseUrl");
		const betterAuthSecret = new sst.Secret("BetterAuthSecret");
		const polarAccessToken = new sst.Secret("PolarAccessToken");
		const googleAiKey = new sst.Secret("GoogleAiKey");
		const redisUrl = new sst.Secret("RedisUrl");
		const redisToken = new sst.Secret("RedisToken");

		// ========================================================================
		// Web App: TanStack Start on Cloudflare Workers
		// ========================================================================
		const web = new sst.cloudflare.Worker("Web", {
			handler: "apps/web/dist/server/index.js",
			url: true,
			build: {
				command: "cd apps/web && bun run build",
			},
			link: [databaseUrl, betterAuthSecret, polarAccessToken],
			environment: {
				CORS_ORIGIN:
					$app.stage === "prod"
						? "https://stackpanel.com"
						: "http://localhost:3001",
				BETTER_AUTH_URL:
					$app.stage === "prod"
						? "https://stackpanel.com"
						: "http://localhost:3001",
				POLAR_SUCCESS_URL:
					$app.stage === "prod"
						? "https://stackpanel.com/success?checkout_id={CHECKOUT_ID}"
						: "http://localhost:3001/success?checkout_id={CHECKOUT_ID}",
			},
			dev: {
				command: "cd apps/web && bun run dev",
				url: "http://localhost:3001",
			},
		});

		// ========================================================================
		// Outputs
		// ========================================================================
		return {
			web: web.url,
		};
	},
});
