import type { AppEnvironment } from "@stackpanel/proto";

/**
 * Variable mapping for display and editing purposes.
 * Represents a flattened view of variables across environments.
 * 
 * With the simplified model, env is now map<string, string>:
 * - Key = ENV_VAR_NAME (e.g., "DATABASE_URL")
 * - Value = literal string OR vals reference (e.g., "ref+sops://...")
 */
export interface AppVariableMapping {
	/** Environment variable name (e.g., "DATABASE_URL") */
	envKey: string;
	/** The value - literal string or vals reference */
	value: string;
	/** Environment names this variable mapping applies to */
	environments: string[];
}

/**
 * Extract environment names from AppEnvironment map.
 * Filters out numeric-only keys (like "0") which are invalid environment names.
 */
export function getEnvironmentNames(
	environments: Record<string, AppEnvironment> | undefined,
): string[] {
	if (!environments) return [];
	// Filter out numeric-only keys (like "0") which are invalid environment names
	return Object.keys(environments).filter((key) => key && !/^\d+$/.test(key));
}

/**
 * Convert environment names to AppEnvironment map (empty environments).
 */
export function toEnvironmentsMap(
	envNames: string[],
): Record<string, AppEnvironment> {
	const result: Record<string, AppEnvironment> = {};
	for (const name of envNames) {
		result[name] = { name, env: {} };
	}
	return result;
}

/**
 * Extract all variables from all environments as a flat list for display.
 * Returns array of { envKey, value, environments } where environments is the
 * list of environment names that contain this variable.
 */
export function flattenEnvironmentVariables(
	environments: Record<string, AppEnvironment> | undefined,
): AppVariableMapping[] {
	if (!environments) return [];

	// Build a map of envKey -> { value, environments[] }
	const variableMap = new Map<
		string,
		{ value: string; environments: string[] }
	>();

	for (const [envName, env] of Object.entries(environments)) {
		for (const [envKey, value] of Object.entries(env.env ?? {})) {
			const existing = variableMap.get(envKey);
			if (existing) {
				existing.environments.push(envName);
			} else {
				variableMap.set(envKey, {
					value: value || "",
					environments: [envName],
				});
			}
		}
	}

	return Array.from(variableMap.entries()).map(([envKey, data]) => ({
		envKey,
		value: data.value,
		environments: data.environments,
	}));
}

/**
 * Build the environments map structure for saving to the API.
 * Variables are stored inside each environment they belong to.
 */
export function buildEnvironmentsMap(
	envNames: string[],
	variableMappings: AppVariableMapping[],
): Record<string, AppEnvironment> {
	const result: Record<string, AppEnvironment> = {};

	// Initialize all environments (filter out invalid/numeric names)
	for (const envName of envNames) {
		const nameStr = String(envName).trim();
		// Skip empty names or numeric-only names (like "0", "1")
		if (!nameStr || /^\d+$/.test(nameStr)) continue;
		result[nameStr] = { name: nameStr, env: {} };
	}

	// Add variables to their respective environments
	for (const mapping of variableMappings) {
		if (!mapping.envKey) continue;

		// Add this variable to each environment it belongs to
		for (const envName of mapping.environments) {
			const nameStr = String(envName).trim();
			if (result[nameStr]) {
				result[nameStr].env[mapping.envKey] = mapping.value;
			}
		}
	}

	return result;
}

/**
 * Check if a value is a vals reference (starts with "ref+").
 */
export function isValsReference(value: string): boolean {
	return value.startsWith("ref+");
}

/**
 * Check if a value is a SOPS secret reference.
 */
export function isSopsReference(value: string): boolean {
	return value.startsWith("ref+sops://");
}

/**
 * Build a SOPS reference for a secret.
 * @param keyGroup - The key group (e.g., "dev", "prod")
 * @param key - The secret key name (e.g., "DATABASE_URL")
 */
export function buildSopsReference(keyGroup: string, key: string): string {
	return `ref+sops://.stackpanel/secrets/${keyGroup}.yaml#/${key}`;
}

/**
 * Build a YAML reference for a plaintext config value.
 * @param key - The config key name (e.g., "LOG_LEVEL")
 */
export function buildYamlReference(key: string): string {
	return `ref+yaml://.stackpanel/secrets/vars.yaml#/${key}`;
}

/**
 * Check if a value is a plaintext YAML reference.
 */
export function isYamlReference(value: string): boolean {
	return value.startsWith("ref+yaml://");
}
