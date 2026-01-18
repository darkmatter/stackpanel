import { AppVariableType } from "@stackpanel/proto";
import type { AppEnvironment } from "@/lib/types";

/**
 * Variable structure for writing to Nix (without the redundant environments field).
 * When variables are nested inside AppEnvironment.variables, they shouldn't have
 * their own environments field.
 */
interface AppVariableForNix {
	key: string;
	type: AppVariableType;
	variable_id: string;
	value?: string;
}

/**
 * Variable mapping for display and editing purposes.
 * Represents a flattened view of variables across environments.
 */
export interface AppVariableMapping {
	envKey: string;
	variableId: string;
	/** Environment names this variable mapping applies to */
	environments: string[];
	/** Optional literal value (when not linked to a workspace variable) */
	literalValue?: string;
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
		result[name] = { name, variables: {} };
	}
	return result;
}

/**
 * Extract all variables from all environments as a flat list for display.
 * Returns array of { envKey, variableId, environments } where environments is the
 * list of environment names that contain this variable.
 */
export function flattenEnvironmentVariables(
	environments: Record<string, AppEnvironment> | undefined,
): AppVariableMapping[] {
	if (!environments) return [];

	// Build a map of envKey -> { variableId, environments[] }
	const variableMap = new Map<
		string,
		{ variableId: string; environments: string[]; literalValue?: string }
	>();

	for (const [envName, env] of Object.entries(environments)) {
		for (const [envKey, variable] of Object.entries(env.variables ?? {})) {
			const existing = variableMap.get(envKey);
			if (existing) {
				existing.environments.push(envName);
			} else {
				variableMap.set(envKey, {
					variableId: variable.variable_id || "",
					environments: [envName],
					literalValue: variable.value,
				});
			}
		}
	}

	return Array.from(variableMap.entries()).map(([envKey, data]) => ({
		envKey,
		variableId: data.variableId,
		environments: data.environments,
		literalValue: data.literalValue,
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
		result[nameStr] = { name: nameStr, variables: {} };
	}

	// Add variables to their respective environments
	for (const mapping of variableMappings) {
		if (!mapping.envKey) continue;

		// Create variable without the 'environments' field since it's redundant
		// when nested inside AppEnvironment.variables
		const variable: AppVariableForNix = {
			key: mapping.envKey,
			type: mapping.variableId
				? AppVariableType.VARIABLE
				: AppVariableType.LITERAL,
			variable_id: mapping.variableId || "",
			...(mapping.literalValue ? { value: mapping.literalValue } : {}),
		};

		// Add this variable to each environment it belongs to
		for (const envName of mapping.environments) {
			const nameStr = String(envName).trim();
			if (result[nameStr]) {
				// Cast to any to allow the slimmer AppVariableForNix type
				result[nameStr].variables[mapping.envKey] = variable as any;
			}
		}
	}

	return result;
}
