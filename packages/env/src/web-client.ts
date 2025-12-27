import { parseEnv, z } from "znv";

// Client-safe environment variables only
// These are embedded in the client bundle and should NOT contain secrets
export const env = parseEnv(
	{ ...import.meta.env },
	{
		NODE_ENV: z
			.enum(["development", "production", "test"])
			.default("development"),
		// Client can use VITE_ prefixed env vars
		VITE_PORT: z.coerce.number().optional(),
	},
);
