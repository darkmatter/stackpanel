import { parseEnv, z } from "znv";

const port = process.env.PORT || process.env.VITE_PORT || process.env.APP_PORT;

export const env = parseEnv(
	{ ...process.env, PORT: port },
	{
		NODE_ENV: z
			.enum(["development", "production", "test"])
			.default("development"),
		PORT: z.coerce.number().default(3000),
		POSTGRES_URL: z.string(),
		BETTER_AUTH_SECRET: z.string().default("supersecret!"),
		APP_HOST: z.string().default("localhost"),
		POLAR_SUCCESS_URL: z
			.string()
			.default("http://localhost:3000/checkout/success"),
		POLAR_ACCESS_TOKEN: z.string().optional(),
		CORS_ORIGIN: z.string().optional(),
	},
);
