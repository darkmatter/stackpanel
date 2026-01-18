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
		const {
			config,
			createDocs,
			createSecrets,
			createWebApp,
			SopsOutput,
		} = await import("./infra/sst");

		const stage = $app.stage;
		const isProd = stage === "prod";

		// Create all resources
		const secrets = createSecrets();
		const docs = createDocs({ isProd });
		const web = createWebApp({ secrets, isProd });

		// Write outputs to SOPS-encrypted file for devenv/CI
		new SopsOutput("Outputs", {
			path: `.stackpanel/secrets/${stage}.yaml`,
			values: {
				web_url: web.url,
				docs_url: docs.url,
				database_url: secrets.databaseUrl.value,
				redis_url: secrets.redisUrl.value,
				redis_token: secrets.redisToken.value,
				better_auth_secret: secrets.betterAuthSecret.value,
				polar_access_token: secrets.polarAccessToken.value,
				google_ai_key: secrets.googleAiKey.value,
			},
		});

		return {
			web: web.url,
			docs: docs.url,
		};
	},
});
