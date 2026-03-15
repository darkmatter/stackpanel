import { useCallback } from "react";
import { toast } from "sonner";
import type { App } from "@/lib/types";
import { usePatchNixData } from "@/lib/use-agent";
import {
	flattenEnvironmentVariables,
	getEnvironmentNames,
} from "../utils";
import {
	buildVariableConfigExpression,
	isVariableLinkReference,
	parseVariableLinkReference,
} from "../../variables/constants";

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
	const patchNixData = usePatchNixData();

	const toPatchPayload = useCallback((value: string) => {
		if (isVariableLinkReference(value)) {
			const variableId = parseVariableLinkReference(value);
			if (variableId) {
				const nextValue = buildVariableConfigExpression(variableId);
				return {
					value: nextValue,
					valueType: nextValue.startsWith("var://") ? "string" : "nix_expr",
				} as const;
			}
		}
		return {
			value: JSON.stringify(value),
			valueType: "string",
		} as const;
	}, []);

	const patchAppPath = useCallback(
		async (appId: string, path: string, value: string, valueType: string) => {
			await patchNixData.mutateAsync({
				entity: "apps",
				key: appId,
				path,
				value,
				valueType,
			});
		},
		[patchNixData],
	);

	const deleteAppPath = useCallback(
		async (appId: string, path: string) => {
			await patchAppPath(appId, path, "", "delete");
		},
		[patchAppPath],
	);

	const ensureEnvironment = useCallback(
		async (appId: string, envName: string) => {
			const existingEnv = resolvedApps?.[appId]?.environments?.[envName];
			if (existingEnv) return;
			await patchAppPath(
				appId,
				`environments.${envName}`,
				JSON.stringify({ name: envName, env: {} }),
				"object",
			);
		},
		[patchAppPath, resolvedApps],
	);

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
				const patchPayload = toPatchPayload(value);
				for (const environment of environments) {
					await ensureEnvironment(appId, environment);
					await patchAppPath(
						appId,
						`environments.${environment}.env.${envKey}`,
						patchPayload.value,
						patchPayload.valueType,
					);
				}
				toast.success(`Added ${envKey} to app`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to add variable",
				);
			}
		},
		[ensureEnvironment, patchAppPath, refetch, toPatchPayload, token],
	);

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
				const existingApp = resolvedApps?.[appId];
				const existingEnvironments = existingApp?.environments ?? {};
				const existingMappings = flattenEnvironmentVariables(existingEnvironments);
				const existingMapping = existingMappings.find((m) => m.envKey === oldEnvKey);
				const currentEnvironments = new Set(existingMapping?.environments ?? []);
				const nextEnvironments = new Set(environments);
				const patchPayload = toPatchPayload(value);

				for (const environment of currentEnvironments) {
					if (oldEnvKey !== newEnvKey || !nextEnvironments.has(environment)) {
						await deleteAppPath(appId, `environments.${environment}.env.${oldEnvKey}`);
					}
				}

				for (const environment of nextEnvironments) {
					await ensureEnvironment(appId, environment);
					await patchAppPath(
						appId,
						`environments.${environment}.env.${newEnvKey}`,
						patchPayload.value,
						patchPayload.valueType,
					);
				}

				toast.success(`Updated ${newEnvKey}`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to update variable",
				);
			}
		},
		[
			deleteAppPath,
			ensureEnvironment,
			patchAppPath,
			refetch,
			resolvedApps,
			toPatchPayload,
			token,
		],
	);

	const handleUpdateEnvironmentsForApp = useCallback(
		async (appId: string, newEnvNames: string[]) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				const existingApp = resolvedApps?.[appId];
				const existingEnvironments = existingApp?.environments ?? {};
				const existingEnvNames = new Set(getEnvironmentNames(existingEnvironments));
				const nextEnvNames = new Set(newEnvNames);

				for (const envName of newEnvNames) {
					if (!existingEnvNames.has(envName)) {
						await ensureEnvironment(appId, envName);
					}
				}

				for (const envName of existingEnvNames) {
					if (!nextEnvNames.has(envName)) {
						await deleteAppPath(appId, `environments.${envName}`);
					}
				}

				toast.success("Updated environments");
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error
						? err.message
						: "Failed to update environments",
				);
			}
		},
		[deleteAppPath, ensureEnvironment, refetch, resolvedApps, token],
	);

	const handleDeleteVariableFromApp = useCallback(
		async (appId: string, envKey: string) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				const existingApp = resolvedApps?.[appId];
				const existingEnvironments = existingApp?.environments ?? {};
				const existingMappings = flattenEnvironmentVariables(existingEnvironments);
				const existingMapping = existingMappings.find((m) => m.envKey === envKey);

				for (const environment of existingMapping?.environments ?? []) {
					await deleteAppPath(appId, `environments.${environment}.env.${envKey}`);
				}

				toast.success(`Removed ${envKey}`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to delete variable",
				);
			}
		},
		[deleteAppPath, refetch, resolvedApps, token],
	);

	const handleUpdateFramework = useCallback(
		async (appId: string, framework: "go" | "bun" | null) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				if (framework == null) {
					await deleteAppPath(appId, "type");
				} else {
					await patchAppPath(appId, "type", JSON.stringify(framework), "string");
				}
				await patchAppPath(
					appId,
					"go.enable",
					JSON.stringify(framework === "go"),
					"bool",
				);
				await patchAppPath(
					appId,
					"bun.enable",
					JSON.stringify(framework === "bun"),
					"bool",
				);

				const label =
					framework === "go"
						? "Go"
						: framework === "bun"
							? "Bun"
							: "None";
				toast.success(`Set framework to ${label} for ${appId}`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error
						? err.message
						: "Failed to update framework setting",
				);
			}
		},
		[deleteAppPath, patchAppPath, refetch, token],
	);

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
				await patchNixData.mutateAsync({
					entity: "apps",
					key: "_root",
					path: appId,
					value: "",
					valueType: "delete",
				});
				toast.success(`Deleted app "${appId}"`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to delete app",
				);
			}
		},
		[patchNixData, refetch, token],
	);

	return {
		handleAddVariableToApp,
		handleUpdateVariableInApp,
		handleUpdateEnvironmentsForApp,
		handleDeleteVariableFromApp,
		handleUpdateFramework,
		handleDeleteApp,
	};
}
