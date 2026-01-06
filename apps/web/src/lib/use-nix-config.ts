"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useAgentSSEEvent } from "./agent-sse-provider";
import { NixClient, type NixClientConfig } from "./nix-client";
import type { App } from "@stackpanel/proto";
import type {
  Service,
  StackpanelConfig,
  Command,
  Commands,
  Variable,
  Variables,
  AppEntity,
  AppEntities,
  ResolvedApp,
} from "./types";

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

const STORAGE_KEY = "stackpanel.agent.token";

function getStoredToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(STORAGE_KEY);
}

function useNixClient(options: NixClientConfig = {}): NixClient {
  const clientRef = useRef<NixClient | null>(null);
  const token = options.token ?? getStoredToken();

  if (!clientRef.current) {
    clientRef.current = new NixClient({
      baseUrl: options.baseUrl,
      token: token ?? undefined,
    });
  }

  // Update token if it changes
  useEffect(() => {
    if (clientRef.current && token) {
      clientRef.current.setToken(token);
    }
  }, [token]);

  return clientRef.current;
}

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
  const client = useNixClient(options);
  const [state, setState] = useState<QueryState<StackpanelConfig>>({
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
        const config = await client.config({ refresh: forceRefresh });
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
      const config = await client.refreshConfig();
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
  const client = useNixClient(options);
  const entityClient = useMemo(
    () => client.entity<T>(entity),
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
  const client = useNixClient(options);
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

// =============================================================================
// Convenience hooks for common entities
// =============================================================================

/**
 * Hook for managing apps configuration.
 */
export function useApps(options: UseNixConfigOptions = {}) {
  return useNixMapData<App>("apps", options);
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
  const client = useNixClient();
  const mapClient = useMemo(() => client.mapEntity<App>("apps"), [client]);
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
  const client = useNixClient();
  const mapClient = useMemo(() => client.mapEntity<App>("apps"), [client]);
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
// Relational Entity Hooks
// =============================================================================

/**
 * Hook for accessing command definitions from commands.nix
 */
export function useCommands(options: UseNixConfigOptions = {}) {
  return useNixMapData<Command>("commands", options);
}

/**
 * Hook for accessing variable definitions from variables.nix
 */
export function useVariables(options: UseNixConfigOptions = {}) {
  return useNixMapData<Variable>("variables", options);
}

/**
 * Hook for accessing app entities from apps.nix (with command/variable IDs)
 */
export function useAppEntities(options: UseNixConfigOptions = {}) {
  return useNixMapData<AppEntity>("apps", options);
}

/**
 * Hook for accessing resolved apps with full command and variable definitions.
 * This joins app data with commands.nix and variables.nix to provide complete entities.
 */
export function useResolvedApps(options: UseNixConfigOptions = {}) {
  const {
    data: apps,
    isLoading: appsLoading,
    error: appsError,
    refetch: refetchApps,
  } = useAppEntities(options);
  const {
    data: commands,
    isLoading: commandsLoading,
    error: commandsError,
    refetch: refetchCommands,
  } = useCommands(options);
  const {
    data: variables,
    isLoading: variablesLoading,
    error: variablesError,
    refetch: refetchVariables,
  } = useVariables(options);

  const isLoading = appsLoading || commandsLoading || variablesLoading;
  const error = appsError || commandsError || variablesError;

  const resolvedApps = useMemo(() => {
    if (!apps || !commands || !variables) return null;

    const result: Record<string, ResolvedApp> = {};

    for (const [appId, app] of Object.entries(apps)) {
      // Resolve command IDs to full command objects
      const resolvedCommands: Command[] = (app.commands ?? [])
        .map((cmdId) => {
          const cmd = commands[cmdId];
          return cmd ? { ...cmd, id: cmdId } : null;
        })
        .filter((cmd): cmd is Command & { id: string } => cmd !== null);

      // Resolve variable IDs to full variable objects
      const resolvedVariables: Variable[] = (app.variables ?? [])
        .map((varId) => {
          const variable = variables[varId];
          return variable ? { ...variable, id: varId } : null;
        })
        .filter((v): v is Variable & { id: string } => v !== null);

      result[appId] = {
        ...app,
        id: appId,
        commands: resolvedCommands,
        variables: resolvedVariables,
      };
    }

    return result;
  }, [apps, commands, variables]);

  const refetch = useCallback(async () => {
    await Promise.all([refetchApps(), refetchCommands(), refetchVariables()]);
  }, [refetchApps, refetchCommands, refetchVariables]);

  return useMemo(
    () => ({
      data: resolvedApps,
      isLoading,
      isError: !!error,
      isSuccess: !!resolvedApps,
      error,
      refetch,
    }),
    [resolvedApps, isLoading, error, refetch],
  );
}

/**
 * Hook to get a single resolved app by ID
 */
export function useResolvedApp(
  appId: string,
  options: UseNixConfigOptions = {},
) {
  const {
    data: apps,
    isLoading,
    isError,
    error,
    refetch,
  } = useResolvedApps(options);

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
 * Hook to find which apps use a specific variable
 */
export function useAppsUsingVariable(
  variableId: string,
  options: UseNixConfigOptions = {},
) {
  const { data: apps, isLoading, error, refetch } = useAppEntities(options);

  const matchingApps = useMemo(() => {
    if (!apps) return null;

    return Object.entries(apps)
      .filter(([_, app]) => app.variables?.includes(variableId))
      .map(([id, app]) => ({ ...app, id }));
  }, [apps, variableId]);

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

/**
 * Hook to find which apps have a specific command
 */
export function useAppsWithCommand(
  commandId: string,
  options: UseNixConfigOptions = {},
) {
  const { data: apps, isLoading, error, refetch } = useAppEntities(options);

  const matchingApps = useMemo(() => {
    if (!apps) return null;

    return Object.entries(apps)
      .filter(([_, app]) => app.commands?.includes(commandId))
      .map(([id, app]) => ({ ...app, id }));
  }, [apps, commandId]);

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

/**
 * Hook to get commands grouped by category
 */
export function useCommandsByCategory(options: UseNixConfigOptions = {}) {
  const { data: commands, isLoading, error, refetch } = useCommands(options);

  const grouped = useMemo(() => {
    if (!commands) return null;

    const result: Record<string, Command[]> = {};

    for (const [id, cmd] of Object.entries(commands)) {
      const category = cmd.category ?? "other";
      if (!result[category]) {
        result[category] = [];
      }
      result[category].push({ ...cmd, id });
    }

    return result;
  }, [commands]);

  return useMemo(
    () => ({
      data: grouped,
      isLoading,
      isError: !!error,
      isSuccess: !!grouped,
      error,
      refetch,
    }),
    [grouped, isLoading, error, refetch],
  );
}

/**
 * Hook to get variables grouped by type
 */
export function useVariablesByType(options: UseNixConfigOptions = {}) {
  const { data: variables, isLoading, error, refetch } = useVariables(options);

  const grouped = useMemo(() => {
    if (!variables) return null;

    const result: Record<string, Variable[]> = {};

    for (const [id, variable] of Object.entries(variables)) {
      const type = variable.type ?? "config";
      if (!result[type]) {
        result[type] = [];
      }
      result[type].push({ ...variable, id });
    }

    return result;
  }, [variables]);

  return useMemo(
    () => ({
      data: grouped,
      isLoading,
      isError: !!error,
      isSuccess: !!grouped,
      error,
      refetch,
    }),
    [grouped, isLoading, error, refetch],
  );
}

// =============================================================================
// Re-exports for convenience
// =============================================================================

export type {
  App,
  Service,
  StackpanelConfig,
  Command,
  Commands,
  Variable,
  Variables,
  AppEntity,
  AppEntities,
  ResolvedApp,
};
