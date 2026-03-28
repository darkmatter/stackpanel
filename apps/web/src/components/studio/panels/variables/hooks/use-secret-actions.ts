import { useCallback } from "react";
import { toast } from "sonner";
import { useAgentClient, useAgentContext } from "@/lib/agent-provider";
import { useVariablesUIStore } from "../store/variables-ui-store";
import { useSecretOperationsStore } from "../store/use-secret-operations";
import { useOptimisticVariables } from "./use-optimistic-variables";

/**
 * Hook for managing secret reveal and delete operations
 * Handles async operations and integrates with Zustand stores
 */
export function useSecretActions(onSuccess?: () => void) {
  const { token } = useAgentContext();
  const agentClient = useAgentClient();
  const { optimisticRemove } = useOptimisticVariables();

  // UI store selectors
  const revealedSecrets = useVariablesUIStore(
    (state: any) => state.revealedSecrets,
  );
  const setRevealedSecret = useVariablesUIStore(
    (state: any) => state.setRevealedSecret,
  );
  const clearRevealedSecret = useVariablesUIStore(
    (state: any) => state.clearRevealedSecret,
  );

  // Operations store selectors
  const setRevealingSecretId = useSecretOperationsStore(
    (state: any) => state.setRevealingSecretId,
  );
  const setRevealError = useSecretOperationsStore(
    (state: any) => state.setRevealError,
  );

  const setDeletingSecretId = useSecretOperationsStore(
    (state: any) => state.setDeletingSecretId,
  );
  const setDeleteError = useSecretOperationsStore(
    (state: any) => state.setDeleteError,
  );
  const clearDeleteState = useSecretOperationsStore(
    (state: any) => state.clearDeleteState,
  );

  /**
   * Decrypt and reveal a secret
   */
  const revealSecret = useCallback(
    async (variableId: string) => {
      if (!token) {
        toast.error("Not connected to agent");
        return;
      }

      // Check if already revealed
      if (revealedSecrets[variableId]?.value) {
        // Hide it
        clearRevealedSecret(variableId);
        return;
      }

      // Set loading state
      setRevealingSecretId(variableId);
      setRevealedSecret(variableId, "", true);
      setRevealError(null);

      try {
        agentClient.setToken(token);
        const result = await agentClient.readAgenixSecret({ id: variableId });
        setRevealedSecret(variableId, result.value, false);

        // Auto-hide after 30 seconds
        const timeoutId = setTimeout(() => {
          clearRevealedSecret(variableId);
        }, 30000);

        // Store timeout ID for cleanup if needed
        return () => clearTimeout(timeoutId);
      } catch (err) {
        const errorMessage =
          err instanceof Error ? err.message : "Failed to decrypt secret";
        setRevealError(errorMessage);
        toast.error(errorMessage);
        clearRevealedSecret(variableId);
      } finally {
        setRevealingSecretId(null);
      }
    },
    [
      token,
      agentClient,
      revealedSecrets,
      setRevealedSecret,
      clearRevealedSecret,
      setRevealingSecretId,
      setRevealError,
    ],
  );

  /**
   * Delete a secret (removes .age file and variables.nix entry)
   */
  const deleteSecret = useCallback(
    async (variableId: string) => {
      if (!token) {
        toast.error("Not connected to agent");
        return;
      }

      if (
        !confirm(
          `Are you sure you want to delete "${variableId}"? This will remove the encrypted secret file.`,
        )
      ) {
        return;
      }

      setDeletingSecretId(variableId);
      setDeleteError(null);

      try {
        agentClient.setToken(token);
        await agentClient.deleteAgenixSecret(variableId);
        optimisticRemove(variableId);
        toast.success(`Deleted secret "${variableId}"`);
        onSuccess?.();
      } catch (err) {
        const errorMessage =
          err instanceof Error ? err.message : "Failed to delete secret";
        setDeleteError(errorMessage);
        toast.error(errorMessage);
      } finally {
        setDeletingSecretId(null);
        clearDeleteState();
      }
    },
    [
      token,
      agentClient,
      onSuccess,
      optimisticRemove,
      setDeletingSecretId,
      setDeleteError,
      clearDeleteState,
    ],
  );

  return {
    revealSecret,
    deleteSecret,
  };
}
