/**
 * useHealthchecks Hook
 *
 * React hook for fetching and managing module healthcheck data.
 * Provides loading states, error handling, and refresh capabilities.
 *
 * Usage:
 *   const { data, isLoading, error, refetch, runChecks } = useHealthchecks();
 *   const { data: moduleHealth } = useModuleHealth('go');
 */

import { useCallback, useEffect, useMemo, useState } from "react";
import { useAgentClient } from "@/lib/agent-provider";
import { useAgentSSEEvent } from "@/lib/agent-sse-provider";
import type { HealthcheckResult, HealthSummary, ModuleHealth } from "./types";

// =============================================================================
// Types
// =============================================================================

interface QueryState<T> {
  data: T | null;
  error: string | null;
  status: "idle" | "loading" | "success" | "error";
  isLoading: boolean;
  isError: boolean;
  isSuccess: boolean;
  dataUpdatedAt: number | null;
}

interface UseHealthchecksOptions {
  /** Whether to fetch on mount */
  enabled?: boolean;
  /** Module to filter by (optional) */
  module?: string;
  /** Whether to use cached results */
  cached?: boolean;
  /** Whether to auto-refetch on SSE events */
  autoRefetch?: boolean;
}

interface UseHealthchecksResult {
  /** Health summary data */
  data: HealthSummary | null;
  /** Error message if request failed */
  error: string | null;
  /** Query status */
  status: "idle" | "loading" | "success" | "error";
  /** Whether data is loading */
  isLoading: boolean;
  /** Whether request errored */
  isError: boolean;
  /** Whether request succeeded */
  isSuccess: boolean;
  /** Timestamp of last successful fetch */
  dataUpdatedAt: number | null;
  /** Whether a refresh is in progress */
  isRefreshing: boolean;
  /** Refetch health data (uses cache) */
  refetch: () => Promise<void>;
  /** Run healthchecks (forces fresh evaluation) */
  runChecks: (module?: string, checkId?: string) => Promise<void>;
}

// =============================================================================
// Main Hook: useHealthchecks
// =============================================================================

/**
 * Hook for fetching and managing healthcheck data.
 *
 * @param options - Configuration options
 * @returns Health summary data and control functions
 */
export function useHealthchecks(
  options: UseHealthchecksOptions = {},
): UseHealthchecksResult {
  const { enabled = true, module, cached = true, autoRefetch = true } = options;
  const client = useAgentClient();

  const [state, setState] = useState<QueryState<HealthSummary>>({
    data: null,
    error: null,
    status: "idle",
    isLoading: false,
    isError: false,
    isSuccess: false,
    dataUpdatedAt: null,
  });

  const [isRefreshing, setIsRefreshing] = useState(false);

  // Fetch health data
  const fetchHealth = useCallback(async () => {
    setState((prev) => ({
      ...prev,
      status: "loading",
      isLoading: true,
      error: null,
    }));

    try {
      const params = new URLSearchParams();
      if (module) params.set("module", module);
      if (!cached) params.set("cached", "false");

      const queryString = params.toString();
      const url = `/api/healthchecks${queryString ? `?${queryString}` : ""}`;

      const response = await client.get<{
        success: boolean;
        data: HealthSummary;
        error?: string;
      }>(url);

      if (!response.success) {
        throw new Error(response.error ?? "Failed to fetch healthchecks");
      }

      setState({
        data: response.data,
        error: null,
        status: "success",
        isLoading: false,
        isError: false,
        isSuccess: true,
        dataUpdatedAt: Date.now(),
      });
    } catch (err) {
      const errorMessage =
        err instanceof Error ? err.message : "Failed to fetch healthchecks";
      setState((prev) => ({
        ...prev,
        error: errorMessage,
        status: "error",
        isLoading: false,
        isError: true,
        isSuccess: false,
      }));
    }
  }, [client, module, cached]);

  // Run healthchecks (POST - forces fresh evaluation)
  const runChecks = useCallback(
    async (targetModule?: string, checkId?: string) => {
      setIsRefreshing(true);

      try {
        const params = new URLSearchParams();
        if (targetModule || module) {
          params.set("module", targetModule || module || "");
        }
        if (checkId) params.set("check", checkId);

        const queryString = params.toString();
        const url = `/api/healthchecks${queryString ? `?${queryString}` : ""}`;

        const response = await client.post<{
          success: boolean;
          data: HealthSummary;
          error?: string;
        }>(url, {});

        if (!response.success) {
          throw new Error(response.error ?? "Failed to run healthchecks");
        }

        setState({
          data: response.data,
          error: null,
          status: "success",
          isLoading: false,
          isError: false,
          isSuccess: true,
          dataUpdatedAt: Date.now(),
        });
      } catch (err) {
        const errorMessage =
          err instanceof Error ? err.message : "Failed to run healthchecks";
        setState((prev) => ({
          ...prev,
          error: errorMessage,
          status: "error",
          isLoading: false,
          isError: true,
          isSuccess: false,
        }));
      } finally {
        setIsRefreshing(false);
      }
    },
    [client, module],
  );

  // Fetch on mount if enabled
  useEffect(() => {
    if (enabled) {
      fetchHealth();
    }
  }, [enabled, fetchHealth]);

  // Subscribe to healthchecks.updated events for auto-refetch
  useAgentSSEEvent("healthchecks.updated", () => {
    if (autoRefetch) {
      fetchHealth();
    }
  });

  return useMemo(
    () => ({
      data: state.data,
      error: state.error,
      status: state.status,
      isLoading: state.isLoading,
      isError: state.isError,
      isSuccess: state.isSuccess,
      dataUpdatedAt: state.dataUpdatedAt,
      isRefreshing,
      refetch: fetchHealth,
      runChecks,
    }),
    [state, isRefreshing, fetchHealth, runChecks],
  );
}

// =============================================================================
// Hook: useModuleHealth
// =============================================================================

interface UseModuleHealthOptions {
  /** Whether to fetch on mount */
  enabled?: boolean;
  /** Whether to use cached results */
  cached?: boolean;
}

interface UseModuleHealthResult {
  /** Module health data */
  data: ModuleHealth | null;
  /** Error message if request failed */
  error: string | null;
  /** Whether data is loading */
  isLoading: boolean;
  /** Whether request errored */
  isError: boolean;
  /** Whether request succeeded */
  isSuccess: boolean;
  /** Refetch health data */
  refetch: () => Promise<void>;
  /** Run healthchecks for this module */
  runChecks: () => Promise<void>;
}

/**
 * Hook for fetching healthcheck data for a specific module.
 *
 * @param moduleName - Name of the module to get health for
 * @param options - Configuration options
 * @returns Module health data and control functions
 */
export function useModuleHealth(
  moduleName: string,
  options: UseModuleHealthOptions = {},
): UseModuleHealthResult {
  const { enabled = true, cached = true } = options;

  const {
    data: summary,
    error,
    isLoading,
    isError,
    isSuccess,
    refetch,
    runChecks: runAllChecks,
  } = useHealthchecks({
    enabled,
    module: moduleName,
    cached,
  });

  const moduleHealth = summary?.modules?.[moduleName] ?? null;

  const runChecks = useCallback(async () => {
    await runAllChecks(moduleName);
  }, [runAllChecks, moduleName]);

  return useMemo(
    () => ({
      data: moduleHealth,
      error,
      isLoading,
      isError,
      isSuccess,
      refetch,
      runChecks,
    }),
    [moduleHealth, error, isLoading, isError, isSuccess, refetch, runChecks],
  );
}

// =============================================================================
// Hook: useHealthcheckResult
// =============================================================================

interface UseHealthcheckResultOptions {
  /** Whether to fetch on mount */
  enabled?: boolean;
}

interface UseHealthcheckResultResult {
  /** Healthcheck result */
  data: HealthcheckResult | null;
  /** Error message if request failed */
  error: string | null;
  /** Whether data is loading */
  isLoading: boolean;
  /** Run this specific healthcheck */
  runCheck: () => Promise<void>;
}

/**
 * Hook for fetching a specific healthcheck result.
 *
 * @param checkId - ID of the healthcheck to get
 * @param options - Configuration options
 * @returns Healthcheck result and control functions
 */
export function useHealthcheckResult(
  checkId: string,
  options: UseHealthcheckResultOptions = {},
): UseHealthcheckResultResult {
  const { enabled = true } = options;
  const client = useAgentClient();

  const [data, setData] = useState<HealthcheckResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  const fetchResult = useCallback(async () => {
    if (!checkId) return;

    setIsLoading(true);
    setError(null);

    try {
      const response = await client.get<{
        success: boolean;
        data: HealthcheckResult;
        error?: string;
      }>(`/api/healthchecks?check=${encodeURIComponent(checkId)}`);
      if (!response.success) {
        throw new Error(response.error ?? "Failed to fetch healthcheck");
      }
      setData(response.data);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Failed to fetch healthcheck",
      );
    } finally {
      setIsLoading(false);
    }
  }, [client, checkId]);

  const runCheck = useCallback(async () => {
    if (!checkId) return;

    setIsLoading(true);
    setError(null);

    try {
      const response = await client.post<{
        success: boolean;
        data: HealthcheckResult;
        error?: string;
      }>(`/api/healthchecks?check=${encodeURIComponent(checkId)}`, {});
      if (!response.success) {
        throw new Error(response.error ?? "Failed to run healthcheck");
      }
      setData(response.data);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Failed to run healthcheck",
      );
    } finally {
      setIsLoading(false);
    }
  }, [client, checkId]);

  useEffect(() => {
    if (enabled) {
      fetchResult();
    }
  }, [enabled, fetchResult]);

  return useMemo(
    () => ({
      data,
      error,
      isLoading,
      runCheck,
    }),
    [data, error, isLoading, runCheck],
  );
}

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Get the overall status from a health summary
 */
export function getOverallStatus(summary: HealthSummary | null): string {
  if (!summary) return "unknown";

  switch (summary.overallStatus) {
    case "HEALTH_STATUS_HEALTHY":
      return "healthy";
    case "HEALTH_STATUS_DEGRADED":
      return "degraded";
    case "HEALTH_STATUS_UNHEALTHY":
      return "unhealthy";
    default:
      return "unknown";
  }
}

/**
 * Count modules by status
 */
export function countModulesByStatus(summary: HealthSummary | null): {
  healthy: number;
  degraded: number;
  unhealthy: number;
  unknown: number;
} {
  const counts = { healthy: 0, degraded: 0, unhealthy: 0, unknown: 0 };

  if (!summary?.modules) return counts;

  for (const moduleHealth of Object.values(summary.modules)) {
    switch (moduleHealth.status) {
      case "HEALTH_STATUS_HEALTHY":
        counts.healthy++;
        break;
      case "HEALTH_STATUS_DEGRADED":
        counts.degraded++;
        break;
      case "HEALTH_STATUS_UNHEALTHY":
        counts.unhealthy++;
        break;
      default:
        counts.unknown++;
    }
  }

  return counts;
}
