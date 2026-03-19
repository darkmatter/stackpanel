/**
 * Hook for managing EditSecretDialog state.
 *
 * Supports SOPS-backed per-variable secrets and the chamber backend.
 */
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import type { AgeIdentityResponse } from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useVariablesBackend } from "@/lib/use-agent";
import type { EditSecretDialogProps } from "./types";

export function useEditSecretDialog(
  props: Pick<
    EditSecretDialogProps,
    | "secretId"
    | "secretKey"
    | "group"
    | "description"
    | "open"
    | "onOpenChange"
    | "onSuccess"
  >,
) {
  const {
    secretId,
    secretKey,
    group: initialGroup,
    description,
    open,
    onOpenChange,
    onSuccess,
  } = props;

  const { token } = useAgentContext();
  const agentClient = useAgentClient();
  const { data: backendData } = useVariablesBackend();
  const isChamber = backendData?.backend === "chamber";

  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [showValue, setShowValue] = useState(false);
  const [value, setValue] = useState("");
  const [newDescription, setNewDescription] = useState(description || "");
  const [group, setGroup] = useState(initialGroup || "secret");
  const [identityPath, setIdentityPath] = useState("");
  const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(
    null,
  );
  const [showSettings, setShowSettings] = useState(false);
  const [decryptError, setDecryptError] = useState<string | null>(null);
  // Load the identity config when dialog opens (vals backend only)
  const loadIdentityConfig = useCallback(async () => {
    if (!token || isChamber) return;
    try {
      const info = await agentClient.getAgeIdentity();
      setIdentityInfo(info);
      if (info.type === "path") {
        setIdentityPath(info.value);
      } else if (info.type === "key") {
        setIdentityPath("(key stored in project)");
      }
    } catch (err) {
      console.warn("Failed to load identity config:", err);
    }
  }, [token, isChamber, agentClient]);

  // Load the secret value
  const loadSecret = useCallback(async () => {
    if (!token) return;

    setIsLoading(true);
    setDecryptError(null);
    setValue("");

    try {
      const result = await agentClient.readAgenixSecret({
        id: secretId,
      });
      setValue(result.value);
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Failed to decrypt secret";

      if (message.includes("not found")) {
        // New secret - start with empty value
        setValue("");
        setDecryptError(null);
        return;
      }

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
  }, [token, secretId, agentClient]);

  // Load when dialog opens
  useEffect(() => {
    if (open && token) {
      loadIdentityConfig();
      if (secretKey) {
        loadSecret();
      }
    }
  }, [
    open,
    token,
    secretKey,
    loadIdentityConfig,
    loadSecret,
  ]);

  // Update group when initialGroup changes
  useEffect(() => {
    if (initialGroup) {
      setGroup(initialGroup);
    }
  }, [initialGroup]);

  const handleSaveIdentity = async (newValue: string) => {
    if (!token) return;
    try {
      const result = await agentClient.setAgeIdentity(newValue);
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
      await agentClient.writeAgenixSecret({
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
    group,
    setGroup,
    identityPath,
    setIdentityPath,
    identityInfo,
    showSettings,
    setShowSettings,
    decryptError,
    isChamber,
    useGroupSecrets: false,

    // Handlers
    handleSaveIdentity,
    handleSave,
    handleRetryDecrypt,
  };
}
