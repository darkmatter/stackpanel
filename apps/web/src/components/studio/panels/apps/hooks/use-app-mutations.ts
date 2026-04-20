import { useCallback } from "react";
import { toast } from "sonner";
import { usePatchNixData } from "@/lib/use-agent";
import {
	buildVariableConfigExpression,
	isVariableLinkReference,
	parseVariableLinkReference,
} from "../../variables/constants";

interface UseAppMutationsOptions {
	token: string | null;
	refetch: () => void;
}

export function useAppMutations({
	token,
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

	const handleAddVariableToApp = useCallback(
		async (
			appId: string,
			envKey: string,
			value: string,
			_environments: string[],
		) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				const patchPayload = toPatchPayload(value);
				await patchAppPath(
					appId,
					`env.${envKey}.value`,
					patchPayload.value,
					patchPayload.valueType,
				);
				toast.success(`Added ${envKey} to app`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to add variable",
				);
			}
		},
		[patchAppPath, refetch, toPatchPayload, token],
	);

	const handleUpdateVariableInApp = useCallback(
		async (
			appId: string,
			oldEnvKey: string,
			newEnvKey: string,
			value: string,
			_environments: string[],
		) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				const patchPayload = toPatchPayload(value);

				if (oldEnvKey !== newEnvKey) {
					await deleteAppPath(appId, `env.${oldEnvKey}`);
				}

				await patchAppPath(
					appId,
					`env.${newEnvKey}.value`,
					patchPayload.value,
					patchPayload.valueType,
				);

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
			patchAppPath,
			refetch,
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
				const nextEnvNames = Array.from(
					new Set(newEnvNames.map((name) => name.trim()).filter(Boolean)),
				);
				await patchAppPath(
					appId,
					"environmentIds",
					JSON.stringify(nextEnvNames),
					"list",
				);

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
		[patchAppPath, refetch, token],
	);

	const handleDeleteVariableFromApp = useCallback(
		async (appId: string, envKey: string) => {
			if (!token) {
				toast.error("Not connected to agent");
				return;
			}

			try {
				await deleteAppPath(appId, `env.${envKey}`);

				toast.success(`Removed ${envKey}`);
				refetch();
			} catch (err) {
				toast.error(
					err instanceof Error ? err.message : "Failed to delete variable",
				);
			}
		},
		[deleteAppPath, refetch, token],
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
