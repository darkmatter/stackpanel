/**
 * Constants and mock data for the app config drawer.
 */
import type { AvailableSecret, AvailableTask, Environment } from "./types";

/**
 * Available task presets for the task editor.
 */
export const AVAILABLE_TASKS: AvailableTask[] = [
	{
		name: "build",
		defaultScript: "npm run build",
		description: "Build for production",
	},
	{
		name: "dev",
		defaultScript: "npm run dev",
		description: "Start dev server",
	},
	{ name: "test", defaultScript: "npm test", description: "Run test suite" },
	{ name: "lint", defaultScript: "npm run lint", description: "Lint code" },
	{
		name: "type-check",
		defaultScript: "tsc --noEmit",
		description: "Type checking",
	},
];

/**
 * Mock available secrets/variables.
 * TODO: Replace with real data from the secrets API.
 */
export const AVAILABLE_SECRETS: AvailableSecret[] = [
	{
		id: "1",
		name: "APP_URL",
		type: "variable",
		value: "https://app.example.com",
	},
	{ id: "2", name: "AUTH_SECRET", type: "secret" },
	{
		id: "3",
		name: "API_URL",
		type: "variable",
		value: "https://api.example.com",
	},
	{
		id: "4",
		name: "DATABASE_URL",
		type: "variable",
		value: "postgres://localhost:5432/db",
	},
	{ id: "5", name: "STRIPE_KEY", type: "secret" },
	{
		id: "6",
		name: "REDIS_URL",
		type: "variable",
		value: "redis://localhost:6379",
	},
];

/**
 * Short names for environment display.
 */
export const ENVIRONMENT_SHORT_NAMES: Record<Environment, string> = {
	development: "dev",
	staging: "stg",
	production: "prod",
};

/**
 * Format environments list for display.
 */
export function formatEnvironments(envs: Environment[]): string {
	if (envs.length === 0) return "No environments";
	return envs.map((e) => ENVIRONMENT_SHORT_NAMES[e]).join(", ");
}
