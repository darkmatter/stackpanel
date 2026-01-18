/**
 * Hook for managing secrets panel state.
 */
import { useCallback, useEffect, useState } from "react";
import { useAgent, useAgentHealth } from "@/lib/use-agent";
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

	const { isPaired } = useAgentHealth();
	const agent = useAgent({ autoConnect: false });

	// Load secrets from agent when paired
	const loadSecrets = useCallback(async () => {
		if (!isPaired || !agent.isConnected) {
			setSecrets(DEMO_SECRETS);
			return;
		}

		setIsLoading(true);
		setError(null);

		try {
			const result = await agent.readSecrets(selectedEnvironment);
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

				// Store values for reveal
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
	}, [isPaired, agent, selectedEnvironment]);

	// Connect agent and load secrets when environment changes
	useEffect(() => {
		if (isPaired && !agent.isConnected) {
			agent.connect().then(() => {
				loadSecrets();
			});
		} else if (isPaired && agent.isConnected) {
			loadSecrets();
		} else {
			setSecrets(DEMO_SECRETS);
		}
	}, [isPaired, agent.isConnected, selectedEnvironment, loadSecrets, agent]);

	const handleAddSecret = async () => {
		if (!newSecretKey.trim() || !newSecretValue.trim()) {
			setError("Both key and value are required");
			return;
		}

		if (!isPaired || !agent.isConnected) {
			setError("Connect to the local agent to add secrets");
			return;
		}

		setIsSaving(true);
		setError(null);

		try {
			await agent.writeSecret(
				selectedEnvironment,
				newSecretKey,
				newSecretValue,
			);
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
		if (!isPaired || !agent.isConnected) {
			setError("Connect to the local agent to delete secrets");
			return;
		}

		try {
			await agent.deleteSecret(selectedEnvironment, key);
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
