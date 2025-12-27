import alchemy from "alchemy";
import { TanStackStart } from "alchemy/cloudflare";
import { config } from "dotenv";

config({ path: "./.env" });

const app = await alchemy("stackpanel");

export const web = await TanStackStart("web", {
	bindings: {
		DATABASE_URL: alchemy.secret.env.DATABASE_URL,
		CORS_ORIGIN: alchemy.env.CORS_ORIGIN,
		BETTER_AUTH_SECRET: alchemy.secret.env.BETTER_AUTH_SECRET,
		BETTER_AUTH_URL: alchemy.env.BETTER_AUTH_URL,
		POLAR_ACCESS_TOKEN: alchemy.secret.env.POLAR_ACCESS_TOKEN,
		POLAR_SUCCESS_URL: alchemy.env.POLAR_SUCCESS_URL,
	},
});

console.log(`Web    -> ${web.url}`);

await app.finalize();
