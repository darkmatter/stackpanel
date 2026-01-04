"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useAgentSSEEvent } from "./agent-sse-provider";
import { NixClient, type NixClientConfig } from "./nix-client";
import type { App, Service, StackpanelConfig } from "./types";

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

	const fetchConfig = useCallback(async () => {
		setState((s) => ({
			...s,
			status: "loading",
			isLoading: true,
			error: null,
		}));

		try {
			const config = await client.config();
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

	return useMemo(
		() => ({
			...state,
			refetch: fetchConfig,
		}),
		[state, fetchConfig],
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
// Re-exports for convenience
// =============================================================================

export type { App, Service, StackpanelConfig };
