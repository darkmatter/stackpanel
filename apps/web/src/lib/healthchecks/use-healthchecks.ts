/**
 * useHealthchecks Hook
 *
 * React hook for fetching and managing module healthcheck data.
 * Provides loading states, error handling, and refresh capabilities.
 *
 * Supports incremental streaming: when checks are run via POST, the backend
 * broadcasts individual `healthcheck.result` SSE events as each check
 * completes, so the UI can update one-by-one instead of waiting for all
 * checks to finish.
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
  /** Set of check IDs currently being evaluated */
  runningCheckIds: Set<string>;
  /** Refetch health data (uses cache) */
  refetch: () => Promise<void>;
  /** Run healthchecks (forces fresh evaluation) */
  runChecks: (module?: string, checkId?: string) => Promise<void>;
}

// =============================================================================
// Helpers
// =============================================================================

/**
 * Merge a single HealthcheckResult into an existing HealthSummary, returning
 * a new object (immutable update). Updates the matching check inside its
 * module, recomputes healthy counts, and recomputes module/overall status.
 */
function mergeSingleResult(
  prev: HealthSummary,
  result: HealthcheckResult,
): HealthSummary {
  const moduleName = result.check?.module;
  if (!moduleName) return prev;

  const existingModule = prev.modules[moduleName];
  if (!existingModule) return prev;

  // Replace (or append) the check result in the module
  let found = false;
  const updatedChecks = existingModule.checks.map((c) => {
    if (c.checkId === result.checkId) {
      found = true;
      return result;
    }
    return c;
  });
  if (!found) {
    updatedChecks.push(result);
  }

  // Recompute module-level aggregates
  let healthyCount = 0;
  let moduleStatus: HealthSummary["overallStatus"] = "HEALTH_STATUS_HEALTHY";
  for (const cr of updatedChecks) {
    if (cr.status === "HEALTH_STATUS_HEALTHY") {
      healthyCount++;
    } else {
      const severity = cr.check?.severity;
      if (severity === "HEALTHCHECK_SEVERITY_CRITICAL") {
        moduleStatus = "HEALTH_STATUS_UNHEALTHY";
      } else if (
        severity === "HEALTHCHECK_SEVERITY_WARNING" &&
        moduleStatus !== "HEALTH_STATUS_UNHEALTHY"
      ) {
        moduleStatus = "HEALTH_STATUS_DEGRADED";
      }
    }
  }

  const updatedModule: ModuleHealth = {
    ...existingModule,
    checks: updatedChecks,
    healthyCount,
    totalCount: updatedChecks.length,
    status: moduleStatus,
    lastUpdated: new Date().toISOString(),
  };

  const updatedModules = { ...prev.modules, [moduleName]: updatedModule };

  // Recompute overall aggregates
  let overallStatus: HealthSummary["overallStatus"] = "HEALTH_STATUS_HEALTHY";
  let totalHealthy = 0;
  let totalChecks = 0;
  for (const mod of Object.values(updatedModules)) {
    totalHealthy += mod.healthyCount;
    totalChecks += mod.totalCount;
    if (mod.status === "HEALTH_STATUS_UNHEALTHY") {
      overallStatus = "HEALTH_STATUS_UNHEALTHY";
    } else if (
      mod.status === "HEALTH_STATUS_DEGRADED" &&
      overallStatus !== "HEALTH_STATUS_UNHEALTHY"
    ) {
      overallStatus = "HEALTH_STATUS_DEGRADED";
    }
  }

  return {
    ...prev,
    modules: updatedModules,
    overallStatus,
    totalHealthy,
    totalChecks,
    lastUpdated: new Date().toISOString(),
  };
}

/**
 * Merge a partial HealthSummary (e.g. from running a single check or module)
 * into a full existing HealthSummary. For each module in the partial summary,
 * merge its checks into the existing module (updating matching checks,
 * appending new ones), then recompute aggregates.
 */
function mergePartialSummary(
  prev: HealthSummary,
  partial: HealthSummary,
): HealthSummary {
  const updatedModules = { ...prev.modules };

  for (const [moduleName, partialModule] of Object.entries(
    partial.modules ?? {},
  )) {
    const existingModule = updatedModules[moduleName];
    if (!existingModule) {
      // New module we haven't seen before — just add it
      updatedModules[moduleName] = partialModule;
      continue;
    }

    // Merge checks: update existing ones, append new ones
    let updatedChecks = [...existingModule.checks];
    for (const partialCheck of partialModule.checks) {
      const idx = updatedChecks.findIndex(
        (c) => c.checkId === partialCheck.checkId,
      );
      if (idx >= 0) {
        updatedChecks[idx] = partialCheck;
      } else {
        updatedChecks.push(partialCheck);
      }
    }

    // Recompute module-level aggregates
    let healthyCount = 0;
    let moduleStatus: HealthSummary["overallStatus"] = "HEALTH_STATUS_HEALTHY";
    for (const cr of updatedChecks) {
      if (cr.status === "HEALTH_STATUS_HEALTHY") {
        healthyCount++;
      } else {
        const severity = cr.check?.severity;
        if (severity === "HEALTHCHECK_SEVERITY_CRITICAL") {
          moduleStatus = "HEALTH_STATUS_UNHEALTHY";
        } else if (
          severity === "HEALTHCHECK_SEVERITY_WARNING" &&
          moduleStatus !== "HEALTH_STATUS_UNHEALTHY"
        ) {
          moduleStatus = "HEALTH_STATUS_DEGRADED";
        }
      }
    }

    updatedModules[moduleName] = {
      ...existingModule,
      checks: updatedChecks,
      healthyCount,
      totalCount: updatedChecks.length,
      status: moduleStatus,
      lastUpdated: partialModule.lastUpdated ?? new Date().toISOString(),
    };
  }

  // Recompute overall aggregates
  let overallStatus: HealthSummary["overallStatus"] = "HEALTH_STATUS_HEALTHY";
  let totalHealthy = 0;
  let totalChecks = 0;
  for (const mod of Object.values(updatedModules)) {
    totalHealthy += mod.healthyCount;
    totalChecks += mod.totalCount;
    if (mod.status === "HEALTH_STATUS_UNHEALTHY") {
      overallStatus = "HEALTH_STATUS_UNHEALTHY";
    } else if (
      mod.status === "HEALTH_STATUS_DEGRADED" &&
      overallStatus !== "HEALTH_STATUS_UNHEALTHY"
    ) {
      overallStatus = "HEALTH_STATUS_DEGRADED";
    }
  }

  return {
    ...prev,
    modules: updatedModules,
    overallStatus,
    totalHealthy,
    totalChecks,
    lastUpdated: partial.lastUpdated ?? new Date().toISOString(),
  };
}

/**
 * Mark a set of check IDs as "running" (UNKNOWN status) in the existing
 * summary so the UI can show spinners immediately.
 */
function markChecksRunning(
  prev: HealthSummary,
  checkIds: Set<string>,
): HealthSummary {
  const updatedModules = { ...prev.modules };

  for (const [moduleName, mod] of Object.entries(updatedModules)) {
    const updatedChecks = mod.checks.map((c) => {
      if (checkIds.has(c.checkId)) {
        return {
          ...c,
          status: "HEALTH_STATUS_UNKNOWN" as const,
          durationMs: 0,
          message: undefined,
          error: undefined,
          output: undefined,
        };
      }
      return c;
    });

    // Only create new object if something changed
    if (updatedChecks !== mod.checks) {
      updatedModules[moduleName] = { ...mod, checks: updatedChecks };
    }
  }

  return { ...prev, modules: updatedModules };
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
  const [runningCheckIds, setRunningCheckIds] = useState<Set<string>>(
    new Set(),
  );

  // Fetch health data
  const fetchHealth = useCallback(async () => {
    setState((prev) => ({
      ...prev,
      // Only set isLoading on the initial fetch (no data yet).
      // Background refetches keep isLoading false so the UI doesn't
      // unmount and lose collapsible/expand state.
      status: prev.data ? prev.status : "loading",
      isLoading: !prev.data,
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

  // Run healthchecks (POST - forces fresh evaluation).
  // The actual result updates come incrementally through SSE events.
  // The POST response is used as the final authoritative state.
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

        // When a specific module or check was targeted, the server returns a
        // partial summary containing only the checks that were run.  Merge that
        // into the existing full summary so other checks are preserved.
        const isPartial = !!(targetModule || module || checkId);
        setState((prev) => {
          const merged =
            isPartial && prev.data
              ? mergePartialSummary(prev.data, response.data)
              : response.data;
          return {
            data: merged,
            error: null,
            status: "success",
            isLoading: false,
            isError: false,
            isSuccess: true,
            dataUpdatedAt: Date.now(),
          };
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
        setRunningCheckIds(new Set());
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

  // ---- SSE: healthchecks.running ----
  // Fired when the server starts evaluating checks. Mark them as "running"
  // in the UI immediately so we can show spinners.
  useAgentSSEEvent<{ checkIds: string[]; module: string }>(
    "healthchecks.running",
    (data) => {
      const ids = new Set(data.checkIds ?? []);
      setRunningCheckIds(ids);

      setState((prev) => {
        if (!prev.data) return prev;
        return {
          ...prev,
          data: markChecksRunning(prev.data, ids),
        };
      });
    },
  );

  // ---- SSE: healthcheck.result ----
  // Fired for each individual check as it completes. Merge the result into
  // the existing summary so it appears immediately in the UI.
  useAgentSSEEvent<HealthcheckResult>("healthcheck.result", (result) => {
    if (!result?.checkId) return;

    // Remove from running set
    setRunningCheckIds((prev) => {
      if (!prev.has(result.checkId)) return prev;
      const next = new Set(prev);
      next.delete(result.checkId);
      return next;
    });

    // Merge into summary
    setState((prev) => {
      if (!prev.data) return prev;
      return {
        ...prev,
        data: mergeSingleResult(prev.data, result),
        status: "success",
        isSuccess: true,
        dataUpdatedAt: Date.now(),
      };
    });
  });

  // ---- SSE: healthchecks.updated ----
  // Final authoritative summary from the server once all checks are done.
  // If the incoming summary is partial (fewer modules than we currently have),
  // merge it into the existing state instead of replacing everything.
  useAgentSSEEvent<HealthSummary>("healthchecks.updated", (data) => {
    if (autoRefetch && data?.modules) {
      setState((prev) => {
        // Detect partial summary: if we already have data and the incoming
        // summary has fewer modules, it's a partial result from running a
        // subset of checks.
        const isPartial =
          prev.data &&
          Object.keys(data.modules).length <
            Object.keys(prev.data.modules).length;
        const merged =
          isPartial && prev.data
            ? mergePartialSummary(prev.data, data)
            : data;
        return {
          ...prev,
          data: merged,
          status: "success",
          isSuccess: true,
          isLoading: false,
          isError: false,
          error: null,
          dataUpdatedAt: Date.now(),
        };
      });
      setRunningCheckIds(new Set());
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
      runningCheckIds,
      refetch: fetchHealth,
      runChecks,
    }),
    [state, isRefreshing, runningCheckIds, fetchHealth, runChecks],
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
