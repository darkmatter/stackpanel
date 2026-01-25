import { useCallback } from "react";
import { toast } from "sonner";
import { useAgentClient } from "@/lib/agent-provider";
import type { App } from "@/lib/types";
import {
	type AppVariableMapping,
	buildEnvironmentsMap,
	flattenEnvironmentVariables,
	getEnvironmentNames,
} from "../utils";

interface UseAppMutationsOptions {
	token: string | null;
	resolvedApps: Record<string, App> | undefined;
	refetch: () => void;
}

export function useAppMutations({
	token,
	resolvedApps,
	refetch,
}: UseAppMutationsOptions) {
	// Get the client at the top level (following Rules of Hooks)
	const client = useAgentClient();

	// Handler for adding a new variable mapping to an app
	// With simplified schema: envKey maps to value (literal or vals reference)
	const handleAddVariableToApp = useCallback(
		async (
			appId: string,
			envKey: string,
			value: string,
			environments: string[],
		) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				if (token) client.setToken(token);
				const appsClient = client.nix.mapEntity<App>("apps");

				// Get existing app to preserve existing environments
				const existingApp = resolvedApps?.[appId];
				const existingEnvironments = existingApp?.environments ?? {};

				// Get existing variable mappings and add the new one
				const existingMappings =
					flattenEnvironmentVariables(existingEnvironments);
				const newMapping: AppVariableMapping = {
					envKey,
					value,
					environments,
				};

				// Merge with existing (replace if same envKey)
				const updatedMappings = [
					...existingMappings.filter((m) => m.envKey !== envKey),
					newMapping,
				];

				// Get all environment names (existing + new)
				const allEnvNames = Array.from(
					new Set([
						...getEnvironmentNames(existingEnvironments),
						...environments,
					]),
				);

				// Build the new environments structure
				const newEnvironments = buildEnvironmentsMap(
					allEnvNames,
					updatedMappings,
				);

				await appsClient.update(appId, {
					environments: newEnvironments,
				});
				toast.success(`Added ${envKey} to app`);

				// Regenerate secrets package in background (works when agent is in devshell)
				client.regenerateSecrets().then((result) => {
					if (result && result.exit_code === 0) {
						toast.success("Secrets package regenerated", { duration: 2000 });
					}
				});

				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to add variable",
				);
			}
		},
		[client, token, resolvedApps, refetch],
	);

	// Handler for updating an existing variable mapping
	// With simplified schema: envKey maps to value (literal or vals reference)
	const handleUpdateVariableInApp = useCallback(
		async (
			appId: string,
			oldEnvKey: string,
			newEnvKey: string,
			value: string,
			environments: string[],
		) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				if (token) client.setToken(token);
				const appsClient = client.nix.mapEntity<App>("apps");

				// Get existing app to preserve existing environments
				const existingApp = resolvedApps?.[appId];
				const existingEnvironments = existingApp?.environments ?? {};

				// Get existing variable mappings, remove the old one, add the updated one
				const existingMappings =
					flattenEnvironmentVariables(existingEnvironments);
				const updatedMapping: AppVariableMapping = {
					envKey: newEnvKey,
					value,
					environments,
				};

				// Remove old mapping and add updated one
				const updatedMappings = [
					...existingMappings.filter((m) => m.envKey !== oldEnvKey),
					updatedMapping,
				];

				// Get all environment names (existing + new)
				const allEnvNames = Array.from(
					new Set([
						...getEnvironmentNames(existingEnvironments),
						...environments,
					]),
				);

				// Build the new environments structure
				const newEnvironments = buildEnvironmentsMap(
					allEnvNames,
					updatedMappings,
				);

				await appsClient.update(appId, {
					environments: newEnvironments,
				});
				toast.success(`Updated ${newEnvKey}`);

				// Regenerate secrets package in background (works when agent is in devshell)
				client.regenerateSecrets().then((result) => {
					if (result && result.exit_code === 0) {
						toast.success("Secrets package regenerated", { duration: 2000 });
					}
				});

				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to update variable",
				);
			}
		},
		[client, token, resolvedApps, refetch],
	);

	// Handler for updating the environments list for an app
	const handleUpdateEnvironmentsForApp = useCallback(
		async (appId: string, newEnvNames: string[]) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				if (token) client.setToken(token);
				const appsClient = client.nix.mapEntity<App>("apps");

				// Get existing app to preserve existing variables
				const existingApp = resolvedApps?.[appId];
				const existingEnvironments = existingApp?.environments ?? {};

				// Get existing variable mappings
				const existingMappings =
					flattenEnvironmentVariables(existingEnvironments);

				// Build the new environments structure with the new env names
				// This preserves variables in environments that still exist
				const newEnvironments = buildEnvironmentsMap(
					newEnvNames,
					existingMappings,
				);

				await appsClient.update(appId, {
					environments: newEnvironments,
				});
				toast.success("Updated environments");
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to update environments",
				);
			}
		},
		[client, token, resolvedApps, refetch],
	);

	// Handler for deleting a variable mapping from an app
	const handleDeleteVariableFromApp = useCallback(
		async (appId: string, envKey: string) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				if (token) client.setToken(token);
				const appsClient = client.nix.mapEntity<App>("apps");

				// Get existing app to preserve existing environments
				const existingApp = resolvedApps?.[appId];
				const existingEnvironments = existingApp?.environments ?? {};

				// Get existing variable mappings and remove the specified one
				const existingMappings =
					flattenEnvironmentVariables(existingEnvironments);
				const updatedMappings = existingMappings.filter(
					(m) => m.envKey !== envKey,
				);

				// Get all environment names from existing
				const allEnvNames = getEnvironmentNames(existingEnvironments);

				// Build the new environments structure
				const newEnvironments = buildEnvironmentsMap(
					allEnvNames,
					updatedMappings,
				);

				await appsClient.update(appId, {
					environments: newEnvironments,
				});
				toast.success(`Removed ${envKey}`);

				// Regenerate secrets package in background (works when agent is in devshell)
				client.regenerateSecrets().then((result) => {
					if (result && result.exit_code === 0) {
						toast.success("Secrets package regenerated", { duration: 2000 });
					}
				});

				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to delete variable",
				);
			}
		},
		[client, token, resolvedApps, refetch],
	);

	// Handler for deleting an app
	const handleDeleteApp = useCallback(
		async (appId: string) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			if (!confirm(`Are you sure you want to delete "${appId}"?`)) {
				return;
			}

			try {
				if (token) client.setToken(token);
				const appsClient = client.nix.mapEntity<App>("apps");

				await appsClient.remove(appId);
				toast.success(`Deleted app "${appId}"`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to delete app",
				);
			}
		},
		[client, token, refetch],
	);

	return {
		handleAddVariableToApp,
		handleUpdateVariableInApp,
		handleUpdateEnvironmentsForApp,
		handleDeleteVariableFromApp,
		handleDeleteApp,
	};
}
