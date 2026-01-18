/**
 * Constants and helpers for the secrets panel.
 */
import type { Secret } from "./types";

/**
 * Demo secrets for when agent is not connected.
 */
export const DEMO_SECRETS: Secret[] = [
	{
		key: "DATABASE_URL",
		environment: "dev",
		type: "connection-string",
	},
	{
		key: "REDIS_URL",
		environment: "dev",
		type: "connection-string",
	},
	{
		key: "JWT_SECRET",
		environment: "dev",
		type: "secret",
	},
	{
		key: "STRIPE_SECRET_KEY",
		environment: "dev",
		type: "api-key",
	},
];

/**
 * Get the color class for a secret type badge.
 */
export function getTypeColor(type: string | undefined): string {
	switch (type) {
		case "connection-string":
			return "bg-blue-500/10 text-blue-400";
		case "api-key":
			return "bg-purple-500/10 text-purple-400";
		case "secret":
			return "bg-accent/10 text-accent";
		case "token":
			return "bg-orange-500/10 text-orange-400";
		default:
			return "bg-muted text-muted-foreground";
	}
}

/**
 * Infer secret type from key name.
 */
export function inferSecretType(key: string): string {
	const keyLower = key.toLowerCase();
	if (keyLower.includes("url") || keyLower.includes("connection")) {
		return "connection-string";
	}
	if (keyLower.includes("api_key") || keyLower.includes("apikey")) {
		return "api-key";
	}
	if (keyLower.includes("token")) {
		return "token";
	}
	if (keyLower.includes("password") || keyLower.includes("pwd")) {
		return "password";
	}
	return "secret";
}
