/**
 * Hook for managing EditSecretDialog state.
 *
 * Supports both:
 * - Group-based SOPS secrets (new): Secrets stored in per-group SOPS files with vals references
 * - Legacy agenix secrets: Individual .age files (deprecated, for backward compatibility)
 * - Chamber (AWS SSM): Uses AWS SSM Parameter Store
 *
 * When a group is specified, secrets are written to `.stackpanel/secrets/groups/<group>.yaml`
 * and the variable value becomes a vals reference: `ref+sops://.stackpanel/secrets/groups/<group>.yaml#/<key>`
 */
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import type { AgeIdentityResponse } from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useVariablesBackend } from "@/lib/use-agent";
import type { EditSecretDialogProps } from "./types";

/** Default group for secrets if none specified */
const DEFAULT_GROUP = "dev";

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

  // Use group-based secrets by default (new architecture)
  const useGroupSecrets = !isChamber && initialGroup !== undefined;

  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [showValue, setShowValue] = useState(false);
  const [value, setValue] = useState("");
  const [newDescription, setNewDescription] = useState(description || "");
  const [group, setGroup] = useState(initialGroup || DEFAULT_GROUP);
  const [identityPath, setIdentityPath] = useState("");
  const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(
    null,
  );
  const [showSettings, setShowSettings] = useState(false);
  const [decryptError, setDecryptError] = useState<string | null>(null);
  const [availableGroups, setAvailableGroups] = useState<string[]>([]);

  // Load available groups
  const loadAvailableGroups = useCallback(async () => {
    if (!token || isChamber) return;
    try {
      const result = await agentClient.listGroupSecrets();
      if ("groups" in result) {
        setAvailableGroups(Object.keys(result.groups));
      }
    } catch (err) {
      console.warn("Failed to load available groups:", err);
      // Default groups if we can't load them
      setAvailableGroups(["dev", "staging", "prod"]);
    }
  }, [token, isChamber, agentClient]);

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
      if (useGroupSecrets) {
        // New group-based secrets: read from group SOPS file
        const result = await agentClient.readGroupSecret({
          key: secretKey,
          group: group,
        });
        setValue(result.value);
      } else {
        // Legacy: read individual .age file via agenix
        const result = await agentClient.readAgenixSecret({
          id: secretId,
        });
        setValue(result.value);
      }
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Failed to decrypt secret";

      // For group secrets, "not found" is expected for new secrets
      if (useGroupSecrets && message.includes("not found")) {
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
  }, [token, secretId, secretKey, group, useGroupSecrets, agentClient]);

  // Load when dialog opens
  useEffect(() => {
    if (open && token) {
      loadIdentityConfig();
      loadAvailableGroups();
      if (secretKey) {
        loadSecret();
      }
    }
  }, [
    open,
    token,
    secretKey,
    loadIdentityConfig,
    loadAvailableGroups,
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
      if (useGroupSecrets) {
        // New group-based secrets: write to group SOPS file and get vals reference
        const result = await agentClient.writeGroupSecret({
          key: secretKey,
          value: value,
          group: group,
          description: newDescription || undefined,
        });

        toast.success(`Secret saved to ${group} group`);
        onOpenChange(false);
        // Pass the vals reference to the callback so the variable value can be updated
        onSuccess(result.valsRef);
      } else {
        // Legacy: write individual .age file
        await agentClient.writeAgenixSecret({
          id: secretId,
          key: secretKey,
          value: value,
          description: newDescription || undefined,
        });

        toast.success("Secret updated successfully");
        onOpenChange(false);
        onSuccess();
      }
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
    availableGroups,
    identityPath,
    setIdentityPath,
    identityInfo,
    showSettings,
    setShowSettings,
    decryptError,
    isChamber,
    useGroupSecrets,

    // Handlers
    handleSaveIdentity,
    handleSave,
    handleRetryDecrypt,
  };
}
