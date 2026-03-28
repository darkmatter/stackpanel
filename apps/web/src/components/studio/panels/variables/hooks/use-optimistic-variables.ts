import { useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";
import { agentQueryKeys } from "@/lib/use-agent";

type VariableEntry = string | { value: string; id?: string };
type VariablesMap = Record<string, VariableEntry>;

/**
 * Provides optimistic cache update helpers for the variables query.
 *
 * Each helper mutates the TanStack Query cache in-place so the UI reflects
 * changes immediately, without waiting for a full refetch round-trip.
 * Callers should still trigger a background refetch/invalidation to reconcile
 * with the server.
 */
export function useOptimisticVariables() {
  const queryClient = useQueryClient();
  const queryKey = agentQueryKeys.variables();

  const optimisticAdd = useCallback(
    (id: string, value: string) => {
      queryClient.setQueryData<VariablesMap>(queryKey, (old) => {
        if (!old) return { [id]: { value, id } };
        return { ...old, [id]: { value, id } };
      });
    },
    [queryClient, queryKey],
  );

  const optimisticUpdate = useCallback(
    (id: string, value: string) => {
      queryClient.setQueryData<VariablesMap>(queryKey, (old) => {
        if (!old) return old;
        const existing = old[id];
        if (typeof existing === "string") {
          return { ...old, [id]: value };
        }
        return { ...old, [id]: { ...existing, value } };
      });
    },
    [queryClient, queryKey],
  );

  const optimisticRemove = useCallback(
    (id: string) => {
      queryClient.setQueryData<VariablesMap>(queryKey, (old) => {
        if (!old) return old;
        const { [id]: _, ...rest } = old;
        return rest;
      });
    },
    [queryClient, queryKey],
  );

  return { optimisticAdd, optimisticUpdate, optimisticRemove };
}
