/**
 * Hook for managing secrets panel state.
 *
 * Uses the SOPS endpoints (/api/sops/*) to read/write/delete secrets
 * from per-environment YAML files (e.g., .stackpanel/secrets/dev.yaml).
 */
import { useCallback, useEffect, useState } from "react";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { DEMO_SECRETS, inferSecretType } from "./constants";
import type { Secret } from "./types";

export function useSecrets() {
	const [searchQuery, setSearchQuery] = useState("");
	const [dialogOpen, setDialogOpen] = useState(false);
	const [selectedEnvironment, setSelectedEnvironment] = useState("dev");
	const [newSecretKey, setNewSecretKey] = useState("");
	const [newSecretValue, setNewSecretValue] = useState("");
	const [showSecret, setShowSecret] = useState<string | null>(null);
	const [secrets, setSecrets] = useState<Secret[]>([]);
	const [secretValues, setSecretValues] = useState<Record<string, string>>({});
	const [isLoading, setIsLoading] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	const [error, setError] = useState<string | null>(null);

	const { token, isConnected } = useAgentContext();
	const agentClient = useAgentClient();
	const isPaired = isConnected && !!token;

	// Load secrets from agent via SOPS read endpoint
	const loadSecrets = useCallback(async () => {
		if (!isPaired) {
			setSecrets(DEMO_SECRETS);
			return;
		}

		setIsLoading(true);
		setError(null);

		try {
			agentClient.setToken(token!);
			const result = await agentClient.readSopsSecrets(selectedEnvironment);

			if (result.exists && result.secrets) {
				const secretsList = Object.entries(result.secrets)
					.filter(([key]) => !key.startsWith("sops"))
					.map(([key, value]) => ({
						key,
						value: String(value),
						environment: selectedEnvironment,
						type: inferSecretType(key),
					}));
				setSecrets(secretsList);

				// Store values for reveal/copy
				const values: Record<string, string> = {};
				for (const [key, value] of Object.entries(result.secrets)) {
					if (!key.startsWith("sops")) {
						values[key] = String(value);
					}
				}
				setSecretValues(values);
			} else {
				setSecrets([]);
				setSecretValues({});
			}
		} catch (err) {
			setError(err instanceof Error ? err.message : "Failed to load secrets");
			setSecrets(DEMO_SECRETS);
		} finally {
			setIsLoading(false);
		}
	}, [isPaired, agentClient, selectedEnvironment, token]);

	// Load secrets when connection or environment changes
	useEffect(() => {
		if (isPaired) {
			loadSecrets();
		} else {
			setSecrets(DEMO_SECRETS);
		}
	}, [isPaired, selectedEnvironment, loadSecrets]);

	const handleAddSecret = async () => {
		if (!newSecretKey.trim() || !newSecretValue.trim()) {
			setError("Both key and value are required");
			return;
		}

		if (!isPaired) {
			setError("Connect to the local agent to add secrets");
			return;
		}

		setIsSaving(true);
		setError(null);

		try {
			agentClient.setToken(token!);
			await agentClient.writeSopsSecret({
				environment: selectedEnvironment,
				key: newSecretKey,
				value: newSecretValue,
			});
			setDialogOpen(false);
			setNewSecretKey("");
			setNewSecretValue("");
			await loadSecrets();
		} catch (err) {
			setError(err instanceof Error ? err.message : "Failed to save secret");
		} finally {
			setIsSaving(false);
		}
	};

	const handleDeleteSecret = async (key: string) => {
		if (!isPaired) {
			setError("Connect to the local agent to delete secrets");
			return;
		}

		try {
			agentClient.setToken(token!);
			await agentClient.deleteSopsSecret(selectedEnvironment, key);
			await loadSecrets();
		} catch (err) {
			setError(err instanceof Error ? err.message : "Failed to delete secret");
		}
	};

	const filteredSecrets = secrets.filter((secret) =>
		secret.key.toLowerCase().includes(searchQuery.toLowerCase()),
	);

	return {
		// State
		searchQuery,
		setSearchQuery,
		dialogOpen,
		setDialogOpen,
		selectedEnvironment,
		setSelectedEnvironment,
		newSecretKey,
		setNewSecretKey,
		newSecretValue,
		setNewSecretValue,
		showSecret,
		setShowSecret,
		secrets,
		secretValues,
		isLoading,
		isSaving,
		error,
		setError,
		isPaired,

		// Computed
		filteredSecrets,

		// Handlers
		loadSecrets,
		handleAddSecret,
		handleDeleteSecret,
	};
}
