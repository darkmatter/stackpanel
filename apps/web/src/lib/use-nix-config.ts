"use client";

import type {
  App,
  AppTask,
  AppVariable,
  Task,
  Tasks,
  Variable,
  Variables,
} from "@stackpanel/proto";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AgentHttpClient, type TurboPackage } from "./agent";
import { useAgentClient } from "./agent-provider";
import { useAgentSSEEvent } from "./agent-sse-provider";
import type { AppEntity, Service, StackpanelConfig } from "./types";
import type { NixConfig } from "./agent";

// Storage key for auth token
const STORAGE_KEY = "stackpanel.agent.token";

/**
 * Get stored auth token from localStorage
 */
function getStoredToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(STORAGE_KEY);
}

// =============================================================================
// Types
// =============================================================================

type QueryStatus = "idle" | "loading" | "success" | "error";

interface QueryState<T> {
  data: T | null;
  error: Error | null;
  status: QueryStatus;
  isLoading: boolean;
  isError: boolean;
  isSuccess: boolean;
  /** Timestamp of last successful fetch */
  dataUpdatedAt: number | null;
}

interface UseNixConfigOptions {
  /** Whether to automatically refetch when config.changed events are received */
  autoRefetch?: boolean;
  /** Base URL for the agent */
  baseUrl?: string;
  /** Auth token (if not using provider) */
  token?: string;
}

interface UseNixDataOptions<T> extends UseNixConfigOptions {
  /** Initial data before first fetch */
  initialData?: T;
}

interface MutationOptions {
  onSuccess?: () => void;
  onError?: (error: Error) => void;
}

interface MutationState {
  isPending: boolean;
  error: Error | null;
}

// =============================================================================
// Shared NixClient instance management
// =============================================================================

// STORAGE_KEY and getStoredToken are no longer needed here as they are in AgentProvider
// useNixClient is replaced by useAgentClient

// =============================================================================
// useNixConfig - Main config hook with SSE-driven reactivity
// =============================================================================

/**
 * Hook to access the full Stackpanel config with SSE-driven automatic updates.
 *
 * @example
 * ```tsx
 * function Dashboard() {
 *   const { data: config, isLoading, refetch } = useNixConfig();
 *
 *   if (isLoading) return <Spinner />;
 *
 *   return (
 *     <div>
 *       <h1>{config?.projectName}</h1>
 *       <p>Base Port: {config?.basePort}</p>
 *     </div>
 *   );
 * }
 * ```
 */
export function useNixConfig(options: UseNixConfigOptions = {}) {
  const { autoRefetch = true } = options;
  const client = useAgentClient();
  if (options.token) client.setToken(options.token);
  const [state, setState] = useState<QueryState<NixConfig>>({
    data: null,
    error: null,
    status: "idle",
    isLoading: false,
    isError: false,
    isSuccess: false,
    dataUpdatedAt: null,
  });
  const [isRefreshing, setIsRefreshing] = useState(false);

  const fetchConfig = useCallback(
    async (forceRefresh = false) => {
      setState((s) => ({
        ...s,
        status: "loading",
        isLoading: true,
        error: null,
      }));

      try {
        const config = await client.nix.config({ refresh: forceRefresh });
        setState({
          data: config,
          error: null,
          status: "success",
          isLoading: false,
          isError: false,
          isSuccess: true,
          dataUpdatedAt: Date.now(),
        });
      } catch (err) {
        setState((s) => ({
          ...s,
          error: err instanceof Error ? err : new Error(String(err)),
          status: "error",
          isLoading: false,
          isError: true,
          isSuccess: false,
        }));
      }
    },
    [client],
  );

  // Force refresh by re-evaluating the flake (slower but guaranteed fresh)
  const forceRefresh = useCallback(async () => {
    setIsRefreshing(true);
    try {
      const config = await client.nix.refreshConfig();
      setState({
        data: config,
        error: null,
        status: "success",
        isLoading: false,
        isError: false,
        isSuccess: true,
        dataUpdatedAt: Date.now(),
      });
    } catch (err) {
      setState((s) => ({
        ...s,
        error: err instanceof Error ? err : new Error(String(err)),
        status: "error",
        isLoading: false,
        isError: true,
        isSuccess: false,
      }));
    } finally {
      setIsRefreshing(false);
    }
  }, [client]);

  // Initial fetch
  useEffect(() => {
    fetchConfig();
  }, [fetchConfig]);

  // Subscribe to config.changed events for auto-refetch
  useAgentSSEEvent("config.changed", () => {
    if (autoRefetch) {
      fetchConfig();
    }
  });

  // Also listen for config.refreshed events (triggered by POST /api/nix/config)
  useAgentSSEEvent("config.refreshed", () => {
    if (autoRefetch) {
      fetchConfig();
    }
  });

  return useMemo(
    () => ({
      ...state,
      refetch: () => fetchConfig(false),
      forceRefresh,
      isRefreshing,
    }),
    [state, fetchConfig, forceRefresh, isRefreshing],
  );
}

// =============================================================================
// useNixData - Entity data hook with SSE reactivity
// =============================================================================

/**
 * Hook to access a Nix data entity with SSE-driven automatic updates.
 *
 * @example
 * ```tsx
 * function AppsList() {
 *   const { data: apps, isLoading, mutate } = useNixData<Record<string, App>>('apps');
 *
 *   const addApp = async () => {
 *     await mutate({
 *       ...apps,
 *       newApp: { port: 3000, tls: false }
 *     });
 *   };
 *
 *   return <ul>{Object.entries(apps ?? {}).map(...)}</ul>;
 * }
 * ```
 */
export function useNixData<T>(
  entity: string,
  options: UseNixDataOptions<T> = {},
) {
  const { autoRefetch = true, initialData } = options;
  const client = useAgentClient();
  const entityClient = useMemo(
    () => client.nix.entity<T>(entity),
    [client, entity],
  );

  const [state, setState] = useState<QueryState<T>>({
    data: initialData ?? null,
    error: null,
    status: initialData ? "success" : "idle",
    isLoading: false,
    isError: false,
    isSuccess: !!initialData,
    dataUpdatedAt: initialData ? Date.now() : null,
  });

  const fetchData = useCallback(async () => {
    setState((s) => ({
      ...s,
      status: "loading",
      isLoading: true,
      error: null,
    }));

    try {
      const data = await entityClient.get();
      setState({
        data,
        error: null,
        status: "success",
        isLoading: false,
        isError: false,
        isSuccess: true,
        dataUpdatedAt: Date.now(),
      });
    } catch (err) {
      setState((s) => ({
        ...s,
        error: err instanceof Error ? err : new Error(String(err)),
        status: "error",
        isLoading: false,
        isError: true,
        isSuccess: false,
      }));
    }
  }, [entityClient]);

  // Mutate and refetch
  const mutate = useCallback(
    async (data: T) => {
      await entityClient.set(data);
      await fetchData();
    },
    [entityClient, fetchData],
  );

  // Initial fetch
  useEffect(() => {
    fetchData();
  }, [fetchData]);

  // Subscribe to config.changed events (data files trigger this too)
  useAgentSSEEvent("config.changed", () => {
    if (autoRefetch) {
      fetchData();
    }
  });

  return useMemo(
    () => ({
      ...state,
      refetch: fetchData,
      mutate,
    }),
    [state, fetchData, mutate],
  );
}

// =============================================================================
// useNixMapData - Map entity hook with SSE reactivity
// =============================================================================

/**
 * Hook for map-style entities with individual key operations.
 *
 * @example
 * ```tsx
 * function AppsManager() {
 *   const apps = useNixMapData<App>('apps');
 *
 *   const addApp = async (name: string, app: App) => {
 *     await apps.set(name, app);
 *   };
 *
 *   return (
 *     <ul>
 *       {Object.entries(apps.data ?? {}).map(([name, app]) => (
 *         <li key={name}>
 *           {name}: port {app.port}
 *           <button onClick={() => apps.remove(name)}>Delete</button>
 *         </li>
 *       ))}
 *     </ul>
 *   );
 * }
 * ```
 */
export function useNixMapData<V>(
  entity: string,
  options: UseNixDataOptions<Record<string, V>> = {},
) {
  const { autoRefetch = true, initialData } = options;
  const client = useAgentClient();
  if (options.token) client.setToken(options.token);
  const mapClient = useMemo(
    () => client.mapEntity<V>(entity),
    [client, entity],
  );

  const [state, setState] = useState<QueryState<Record<string, V>>>({
    data: initialData ?? null,
    error: null,
    status: initialData ? "success" : "idle",
    isLoading: false,
    isError: false,
    isSuccess: !!initialData,
    dataUpdatedAt: initialData ? Date.now() : null,
  });

  const fetchData = useCallback(async () => {
    setState((s) => ({
      ...s,
      status: "loading",
      isLoading: true,
      error: null,
    }));

    try {
      const data = await mapClient.all();
      setState({
        data,
        error: null,
        status: "success",
        isLoading: false,
        isError: false,
        isSuccess: true,
        dataUpdatedAt: Date.now(),
      });
    } catch (err) {
      setState((s) => ({
        ...s,
        error: err instanceof Error ? err : new Error(String(err)),
        status: "error",
        isLoading: false,
        isError: true,
        isSuccess: false,
      }));
    }
  }, [mapClient]);

  // Key-level operations
  const set = useCallback(
    async (key: string, value: V) => {
      await mapClient.set(key, value);
      await fetchData();
    },
    [mapClient, fetchData],
  );

  const update = useCallback(
    async (key: string, updates: Partial<V>) => {
      await mapClient.update(key, updates);
      await fetchData();
    },
    [mapClient, fetchData],
  );

  const remove = useCallback(
    async (key: string) => {
      await mapClient.remove(key);
      await fetchData();
    },
    [mapClient, fetchData],
  );

  // Initial fetch
  useEffect(() => {
    fetchData();
  }, [fetchData]);

  // Subscribe to config.changed events
  useAgentSSEEvent("config.changed", () => {
    if (autoRefetch) {
      fetchData();
    }
  });

  return useMemo(
    () => ({
      ...state,
      refetch: fetchData,
      set,
      update,
      remove,
    }),
    [state, fetchData, set, update, remove],
  );
}

/**
 * Hook for managing services configuration.
 */
export function useServices(options: UseNixConfigOptions = {}) {
  return useNixMapData<Service>("services", options);
}

// =============================================================================
// Mutation hooks for apps
// =============================================================================

/**
 * Hook for updating an app in the Nix configuration.
 *
 * @example
 * ```tsx
 * const updateApp = useUpdateApp({
 *   onSuccess: () => console.log('App updated!'),
 * });
 *
 * updateApp.mutate({ key: 'web', data: { name: 'Web App', path: 'apps/web' } });
 * ```
 */
export function useUpdateApp(options: MutationOptions = {}) {
  const client = useAgentClient();
  const mapClient = useMemo(() => client.nix.mapEntity<App>("apps"), [client]);
  const [state, setState] = useState<MutationState>({
    isPending: false,
    error: null,
  });

  const mutate = useCallback(
    async ({ key, data }: { key: string; data: Partial<App> }) => {
      setState({ isPending: true, error: null });
      try {
        await mapClient.update(key, data);
        setState({ isPending: false, error: null });
        options.onSuccess?.();
      } catch (err) {
        const error = err instanceof Error ? err : new Error(String(err));
        setState({ isPending: false, error });
        options.onError?.(error);
      }
    },
    [mapClient, options],
  );

  return useMemo(
    () => ({
      ...state,
      mutate,
    }),
    [state, mutate],
  );
}

/**
 * Hook for deleting an app from the Nix configuration.
 *
 * @example
 * ```tsx
 * const deleteApp = useDeleteApp({
 *   onSuccess: () => console.log('App deleted!'),
 * });
 *
 * deleteApp.mutate('web');
 * ```
 */
export function useDeleteApp(options: MutationOptions = {}) {
  const client = useAgentClient();
  const mapClient = useMemo(() => client.nix.mapEntity<App>("apps"), [client]);
  const [state, setState] = useState<MutationState>({
    isPending: false,
    error: null,
  });

  const mutate = useCallback(
    async (key: string) => {
      setState({ isPending: true, error: null });
      try {
        await mapClient.remove(key);
        setState({ isPending: false, error: null });
        options.onSuccess?.();
      } catch (err) {
        const error = err instanceof Error ? err : new Error(String(err));
        setState({ isPending: false, error });
        options.onError?.(error);
      }
    },
    [mapClient, options],
  );

  return useMemo(
    () => ({
      ...state,
      mutate,
    }),
    [state, mutate],
  );
}

// =============================================================================
// Entity Hooks - Using Proto Types
// =============================================================================

/**
 * Hook for accessing workspace-level task definitions from tasks.nix
 * Task = { exec, description?, cwd?, env }
 */
export function useTasks(options: UseNixConfigOptions = {}) {
  return useNixMapData<Task>("tasks", options);
}

/**
 * Hook for accessing workspace-level variable definitions from variables.nix
 * Variable = { key, description?, type, value }
 */
export function useVariables(options: UseNixConfigOptions = {}) {
  return useNixMapData<Variable>("variables", options);
}

/**
 * Hook for accessing apps from apps.nix
 * App = { name, description?, path, type?, port?, domain?, tasks, variables }
 * - tasks is a map where key = task name, value = AppTask
 * - variables is a map where key = variable name, value = AppVariable
 */
export function useApps(options: UseNixConfigOptions = {}) {
  return useNixMapData<App>("apps", options);
}

/**
 * Hook to get a single app by ID
 */
export function useApp(appId: string, options: UseNixConfigOptions = {}) {
  const { data: apps, isLoading, isError, error, refetch } = useApps(options);

  const app = useMemo(() => {
    if (!apps) return null;
    return apps[appId] ?? null;
  }, [apps, appId]);

  return useMemo(
    () => ({
      data: app,
      isLoading,
      isError,
      isSuccess: !!app,
      error,
      refetch,
    }),
    [app, isLoading, isError, error, refetch],
  );
}

/**
 * Hook to find which apps have a specific variable
 */
export function useAppsWithVariable(
  variableName: string,
  options: UseNixConfigOptions = {},
) {
  const { data: apps, isLoading, error, refetch } = useApps(options);

  const matchingApps = useMemo(() => {
    if (!apps) return null;

    return Object.entries(apps)
      .filter(([_, app]) => variableName in (app.variables ?? {}))
      .map(([id, app]) => ({ ...app, id }));
  }, [apps, variableName]);

  return useMemo(
    () => ({
      data: matchingApps,
      isLoading,
      isError: !!error,
      isSuccess: !!matchingApps,
      error,
      refetch,
    }),
    [matchingApps, isLoading, error, refetch],
  );
}

// =============================================================================
// Turbo Package Graph Hooks
// =============================================================================

/**
 * Hook for fetching the turbo package graph with tasks.
 * This is the source of truth for available tasks in the monorepo.
 *
 * @example
 * ```tsx
 * function TasksList() {
 *   const { packages, allTasks, isLoading, refetch } = useTurboPackages();
 *
 *   return (
 *     <ul>
 *       {allTasks.map(task => <li key={task}>{task}</li>)}
 *     </ul>
 *   );
 * }
 * ```
 */
export function useTurboPackages(options: UseNixConfigOptions = {}) {
  const { autoRefetch = true, token: optionToken, baseUrl } = options;
  const storedToken = getStoredToken();
  const token = optionToken ?? storedToken;

  const [packages, setPackages] = useState<TurboPackage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const fetchPackages = useCallback(async () => {
    if (!token) return;

    setIsLoading(true);
    setError(null);

    try {
      const [host, portStr] = (baseUrl ?? "localhost:9876")
        .replace(/^https?:\/\//, "")
        .split(":");
      const port = portStr ? parseInt(portStr, 10) : 9876;
      const client = new AgentHttpClient(host, port, token);
      const result = await client.getPackageGraph({ excludeRoot: true });
      setPackages(result);
    } catch (err) {
      setError(
        err instanceof Error ? err : new Error("Failed to fetch packages"),
      );
    } finally {
      setIsLoading(false);
    }
  }, [token, baseUrl]);

  // Initial fetch
  useEffect(() => {
    fetchPackages();
  }, [fetchPackages]);

  // Subscribe to turbo.changed events for auto-refetch
  useAgentSSEEvent("turbo.changed", () => {
    if (autoRefetch) {
      fetchPackages();
    }
  });

  // Also refetch on config changes since turbo.json might be generated
  useAgentSSEEvent("config.changed", () => {
    if (autoRefetch) {
      fetchPackages();
    }
  });

  // Get all unique tasks from the package graph
  const allTasks = useMemo(() => {
    const taskSet = new Set<string>();
    for (const pkg of packages) {
      for (const task of pkg.tasks) {
        taskSet.add(task.name);
      }
    }
    return Array.from(taskSet).sort();
  }, [packages]);

  // Get tasks as a map for easier lookup (simple string -> name map for UI)
  const tasksMap = useMemo((): Record<string, { name: string }> => {
    const map: Record<string, { name: string }> = {};
    for (const taskName of allTasks) {
      map[taskName] = { name: taskName };
    }
    return map;
  }, [allTasks]);

  // Get tasks for a specific package
  const getTasksForPackage = useCallback(
    (packageName: string): Array<{ name: string }> => {
      const pkg = packages.find((p) => p.name === packageName);
      if (!pkg) return [];
      return pkg.tasks.map((t) => ({ name: t.name }));
    },
    [packages],
  );

  return useMemo(
    () => ({
      /** All packages with their tasks */
      packages,
      /** All unique task names across all packages */
      allTasks,
      /** Tasks as a map for compatibility with existing code */
      tasksMap,
      /** Get tasks for a specific package */
      getTasksForPackage,
      /** Loading state */
      isLoading,
      /** Error state */
      isError: !!error,
      /** Success state */
      isSuccess: packages.length > 0 && !isLoading && !error,
      /** Error object */
      error,
      /** Refetch the package graph */
      refetch: fetchPackages,
    }),
    [
      packages,
      allTasks,
      tasksMap,
      getTasksForPackage,
      isLoading,
      error,
      fetchPackages,
    ],
  );
}

/**
 * Hook for accessing turbo tasks from the package graph.
 * This is a convenience wrapper around useTurboPackages that returns just the tasks.
 *
 * Note: For Nix-based task definitions, use the useTasks hook from Entity Hooks section.
 */
export function useTurboTasks(options: UseNixConfigOptions = {}) {
  const { tasksMap, isLoading, isError, isSuccess, error, refetch } =
    useTurboPackages(options);

  return useMemo(
    () => ({
      data: tasksMap,
      isLoading,
      isError,
      isSuccess,
      error,
      refetch,
    }),
    [tasksMap, isLoading, isError, isSuccess, error, refetch],
  );
}

// =============================================================================
// Re-exports for convenience
// =============================================================================

export type {
  App,
  Service,
  Variable,
  Variables,
  AppEntity,
  Task,
  Tasks,
  TurboPackage,
};

// Also re-export NixConfig for consumers that need the full config type
export type { NixConfig, StackpanelConfig };
