/**
 * Hook for managing EditSecretDialog state.
 */
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import type { AgeIdentityResponse } from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import type { EditSecretDialogProps } from "./types";

export function useEditSecretDialog(
	props: Pick<EditSecretDialogProps, "secretId" | "secretKey" | "description" | "open" | "onOpenChange" | "onSuccess">
) {
	const { secretId, secretKey, description, open, onOpenChange, onSuccess } = props;
	const { token } = useAgentContext();
	const agentClient = useAgentClient();

	const [isLoading, setIsLoading] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	const [showValue, setShowValue] = useState(false);
	const [value, setValue] = useState("");
	const [newDescription, setNewDescription] = useState(description || "");
	const [identityPath, setIdentityPath] = useState("");
	const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(null);
	const [showSettings, setShowSettings] = useState(false);
	const [decryptError, setDecryptError] = useState<string | null>(null);

	// Load the identity config when dialog opens
	const loadIdentityConfig = useCallback(async () => {
		if (!token) return;
		try {
			const client = agentClient;
			const info = await client.getAgeIdentity();
			setIdentityInfo(info);
			if (info.type === "path") {
				setIdentityPath(info.value);
			} else if (info.type === "key") {
				setIdentityPath("(key stored in project)");
			}
		} catch (err) {
			console.warn("Failed to load identity config:", err);
		}
	}, [token]);

	// Load the secret value
	const loadSecret = useCallback(async () => {
		if (!token) return;

		setIsLoading(true);
		setDecryptError(null);
		setValue("");

		try {
			const client = agentClient;
			const result = await client.readAgenixSecret({
				id: secretId,
			});
			setValue(result.value);
		} catch (err) {
			const message =
				err instanceof Error ? err.message : "Failed to decrypt secret";
			setDecryptError(message);
			// Show settings if it's an identity file issue
			if (
				message.includes("identity") ||
				message.includes("key") ||
				message.includes("configure")
			) {
				setShowSettings(true);
			}
		} finally {
			setIsLoading(false);
		}
	}, [token, secretId]);

	// Load when dialog opens
	useEffect(() => {
		if (open && token && secretId) {
			loadIdentityConfig();
			loadSecret();
		}
	}, [open, token, secretId, loadIdentityConfig, loadSecret]);

	const handleSaveIdentity = async (newValue: string) => {
		if (!token) return;
		try {
			const client = agentClient;
			const result = await client.setAgeIdentity(newValue);
			setIdentityInfo(result);
			if (result.type === "path") {
				setIdentityPath(result.value);
			} else if (result.type === "key") {
				setIdentityPath("(key stored in project)");
			} else {
				setIdentityPath("");
			}
			toast.success("Identity saved");
			// Retry decryption with new identity
			loadSecret();
		} catch (err) {
			toast.error(
				err instanceof Error ? err.message : "Failed to save identity",
			);
		}
	};

	const handleSave = async () => {
		if (!token || !value.trim()) {
			toast.error("Please enter a value");
			return;
		}

		setIsSaving(true);
		try {
			const client = agentClient;
			await client.writeAgenixSecret({
				id: secretId,
				key: secretKey,
				value: value,
				description: newDescription || undefined,
			});

			toast.success("Secret updated successfully");
			onOpenChange(false);
			onSuccess();
		} catch (err) {
			toast.error(
				err instanceof Error ? err.message : "Failed to update secret",
			);
		} finally {
			setIsSaving(false);
		}
	};

	const handleRetryDecrypt = () => {
		loadSecret();
	};

	return {
		// State
		isLoading,
		isSaving,
		showValue,
		setShowValue,
		value,
		setValue,
		newDescription,
		setNewDescription,
		identityPath,
		setIdentityPath,
		identityInfo,
		showSettings,
		setShowSettings,
		decryptError,

		// Handlers
		handleSaveIdentity,
		handleSave,
		handleRetryDecrypt,
	};
}
