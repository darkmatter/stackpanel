/**
 * Hook for managing SST configuration state.
 */
import { useCallback, useEffect, useState } from "react";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useNixConfig, useNixData } from "@/lib/use-nix-config";
import { DEFAULT_SST_DATA, mergeWithDefaults } from "./constants";
import type { SSTData, SSTResource, SSTStatus } from "./types";

export interface UseSSTConfigResult {
	// Form state
	formData: SSTData;
	hasChanges: boolean;
	isSaving: boolean;
	updateField: <K extends keyof SSTData>(key: K, value: SSTData[K]) => void;
	updateNestedField: (
		parent: "kms" | "oidc" | "iam",
		key: string,
		value: unknown,
	) => void;
	updateOidcProviderField: (
		provider: "github-actions" | "flyio" | "roles-anywhere",
		key: string,
		value: string,
	) => void;
	handleSave: () => Promise<void>;

	// Runtime state
	status: SSTStatus | null;
	outputs: Record<string, unknown>;
	resources: SSTResource[];
	isLoading: boolean;
	error: string | null;

	// Deploy actions
	isDeploying: boolean;
	deployOutput: string;
	deployStage: string;
	setDeployStage: (stage: string) => void;
	handleDeploy: () => Promise<void>;
	handleRemove: () => Promise<void>;
	loadStatus: () => Promise<void>;

	// Derived values
	projectName: string;
	currentProvider: string;
}

export function useSSTConfig(): UseSSTConfigResult {
	const { token, isConnected } = useAgentContext();
	const agentClient = useAgentClient();

	// Get main stackpanel config for inheriting defaults
	const { data: mainConfig } = useNixConfig();

	// Extract inherited values from mainConfig
	const projectName =
		((mainConfig as Record<string, unknown>)?.name as string) ?? "";
	const githubRepo =
		((mainConfig as Record<string, unknown>)?.github as string) ?? "";
	const awsConfig = (mainConfig as Record<string, unknown>)?.aws as
		| Record<string, unknown>
		| undefined;
	const rolesAnywhere = awsConfig?.["roles-anywhere"] as
		| Record<string, unknown>
		| undefined;

	// Parse github repo into org/repo
	const [githubOrg, githubRepoName] = githubRepo.includes("/")
		? githubRepo.split("/")
		: ["", "*"];

	// Inherited AWS config
	const inheritedRegion = (rolesAnywhere?.region as string) ?? "us-west-2";
	const inheritedAccountId = (rolesAnywhere?.["account-id"] as string) ?? "";

	// Use useNixData for editable SST configuration
	const {
		data: sstData,
		mutate: setSstData,
		isLoading: isDataLoading,
	} = useNixData<SSTData>("sst", { initialData: DEFAULT_SST_DATA });

	// Local form state
	const [formData, setFormData] = useState<SSTData>(DEFAULT_SST_DATA);
	const [hasChanges, setHasChanges] = useState(false);
	const [isSaving, setIsSaving] = useState(false);

	// Runtime status
	const [status, setStatus] = useState<SSTStatus | null>(null);
	const [outputs, setOutputs] = useState<Record<string, unknown>>({});
	const [resources, setResources] = useState<SSTResource[]>([]);
	const [isLoading, setIsLoading] = useState(true);
	const [isDeploying, setIsDeploying] = useState(false);
	const [deployOutput, setDeployOutput] = useState("");
	const [deployStage, setDeployStage] = useState("dev");
	const [error, setError] = useState<string | null>(null);

	// Sync form data when sstData changes, merging inherited values
	useEffect(() => {
		if (sstData) {
			const merged = mergeWithDefaults(sstData);

			// Prefill project name from stackpanel.name
			if (!merged["project-name"] && projectName) {
				merged["project-name"] = projectName;
			}

			// Prefill region from stackpanel.aws.roles-anywhere.region
			if (!merged.region || merged.region === "us-west-2") {
				merged.region = inheritedRegion;
			}

			// Prefill account-id from stackpanel.aws.roles-anywhere.account-id
			if (!merged["account-id"] && inheritedAccountId) {
				merged["account-id"] = inheritedAccountId;
			}

			// Prefill KMS alias from project name
			if (!merged.kms?.alias && projectName) {
				merged.kms = { ...merged.kms, alias: `${projectName}-secrets` };
			}

			// Prefill IAM role name from project name
			if (!merged.iam?.["role-name"] && projectName) {
				merged.iam = {
					...merged.iam,
					"role-name": `${projectName}-secrets-role`,
				};
			}

			// Prefill GitHub Actions org/repo from stackpanel.github
			if (!merged.oidc?.["github-actions"]?.org && githubOrg) {
				merged.oidc = {
					...merged.oidc,
					"github-actions": {
						...merged.oidc?.["github-actions"],
						org: githubOrg,
						repo: githubRepoName || "*",
					},
				};
			}

			setFormData(merged);
			setHasChanges(false);
		}
	}, [
		sstData,
		projectName,
		inheritedRegion,
		inheritedAccountId,
		githubOrg,
		githubRepoName,
	]);

	// Update form field
	const updateField = <K extends keyof SSTData>(key: K, value: SSTData[K]) => {
		setFormData((prev) => ({ ...prev, [key]: value }));
		setHasChanges(true);
	};

	// Update nested field
	const updateNestedField = (
		parent: "kms" | "oidc" | "iam",
		key: string,
		value: unknown,
	) => {
		setFormData((prev) => ({
			...prev,
			[parent]: { ...prev[parent], [key]: value },
		}));
		setHasChanges(true);
	};

	// Update OIDC provider-specific field
	const updateOidcProviderField = (
		provider: "github-actions" | "flyio" | "roles-anywhere",
		key: string,
		value: string,
	) => {
		setFormData((prev) => ({
			...prev,
			oidc: {
				...prev.oidc,
				[provider]: {
					...(prev.oidc?.[provider] as Record<string, string>),
					[key]: value,
				},
			},
		}));
		setHasChanges(true);
	};

	// Save configuration
	const handleSave = useCallback(async () => {
		if (!hasChanges || isSaving) return;
		setIsSaving(true);
		setError(null);
		try {
			await setSstData(formData);
			setHasChanges(false);
		} catch (err) {
			console.error("Failed to save SST config:", err);
			setError(err instanceof Error ? err.message : "Failed to save");
		} finally {
			setIsSaving(false);
		}
	}, [formData, hasChanges, isSaving, setSstData]);

	// Load runtime status from agent
	const loadStatus = useCallback(async () => {
		if (!token || !isConnected) return;
		setIsLoading(true);
		setError(null);
		try {
			const client = agentClient;
			const [statusRes, outputsRes, resourcesRes] = await Promise.allSettled([
				client.getSSTStatus(),
				client.getSSTOutputs(),
				client.getSSTResources(),
			]);
			if (statusRes.status === "fulfilled" && statusRes.value) {
				setStatus(statusRes.value);
			}
			if (outputsRes.status === "fulfilled" && outputsRes.value) {
				setOutputs(outputsRes.value);
			}
			if (resourcesRes.status === "fulfilled" && resourcesRes.value) {
				setResources(resourcesRes.value);
			}
		} catch (err) {
			console.error("Failed to load SST status:", err);
			setError(err instanceof Error ? err.message : "Failed to load status");
		} finally {
			setIsLoading(false);
		}
	}, [token, isConnected]);

	// Initial load
	useEffect(() => {
		loadStatus();
	}, [loadStatus]);

	const handleDeploy = useCallback(async () => {
		if (!token || !isConnected || isDeploying) return;
		setIsDeploying(true);
		setDeployOutput("");
		setError(null);
		try {
			const client = agentClient;
			const result = await client.deploySSTInfra(deployStage);
			setDeployOutput(result.output || "");
			if (result.success) {
				await loadStatus();
			} else {
				setError(result.error || "Deployment failed");
			}
		} catch (err) {
			console.error("Deployment failed:", err);
			setError(err instanceof Error ? err.message : "Deployment failed");
		} finally {
			setIsDeploying(false);
		}
	}, [token, isConnected, isDeploying, deployStage, loadStatus]);

	const handleRemove = useCallback(async () => {
		if (!token || !isConnected) return;
		if (
			!confirm(
				`Are you sure you want to remove the ${deployStage} infrastructure?`,
			)
		) {
			return;
		}
		setIsDeploying(true);
		setDeployOutput("");
		setError(null);
		try {
			const client = agentClient;
			const result = await client.removeSSTInfra(deployStage);
			setDeployOutput(result.output || "");
			if (!result.success) {
				setError(result.error || "Removal failed");
			}
			await loadStatus();
		} catch (err) {
			console.error("Removal failed:", err);
			setError(err instanceof Error ? err.message : "Removal failed");
		} finally {
			setIsDeploying(false);
		}
	}, [token, isConnected, deployStage, loadStatus]);

	const currentProvider = formData.oidc?.provider ?? "github-actions";

	return {
		// Form state
		formData,
		hasChanges,
		isSaving,
		updateField,
		updateNestedField,
		updateOidcProviderField,
		handleSave,

		// Runtime state
		status,
		outputs,
		resources,
		isLoading: isLoading && isDataLoading,
		error,

		// Deploy actions
		isDeploying,
		deployOutput,
		deployStage,
		setDeployStage,
		handleDeploy,
		handleRemove,
		loadStatus,

		// Derived values
		projectName,
		currentProvider,
	};
}
