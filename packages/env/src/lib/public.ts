/**
 * Filter function for environment variables
 * @param [key, value] - The key and value of the environment variable
 * @returns True if the key is a public environment variable
 */
export function filterKey([key]: [string, unknown]): boolean {
	return (
		key.startsWith("VITE_") || key.startsWith("PUBLIC_") || key === "NODE_ENV"
	);
}

/**
 * Filter the environment variables to only include public environment variables
 * @param obj - The environment variables
 * @returns The public environment variables
 */
export function filterPublicEnv(obj: Record<string, unknown>) {
	return Object.fromEntries(Object.entries(obj).filter(filterKey));
}
