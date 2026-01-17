"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AgentHttpClient } from "./agent";
import { getNixpkgsCache } from "./nixpkgs-cache";
import type { NixpkgsPackage } from "./types";

const STORAGE_KEY = "stackpanel.agent.token";

function getStoredToken(): string | null {
	if (typeof window === "undefined") return null;
	return localStorage.getItem(STORAGE_KEY);
}

export interface UseNixpkgsSearchOptions {
	/** Agent host */
	host?: string;
	/** Agent port */
	port?: number;
	/** Max results per page (default: 20) */
	limit?: number;
	/** Debounce delay in ms (default: 300) */
	debounceMs?: number;
}

export type DataSource = "cache" | "fresh" | "local";

export interface UseNixpkgsSearchReturn {
	/** Current search query */
	query: string;
	/** Set the search query */
	setQuery: (query: string) => void;
	/** Search results */
	packages: NixpkgsPackage[];
	/** Total number of results */
	total: number;
	/** Whether a search is in progress */
	isLoading: boolean;
	/** Whether fresh data is being fetched (cache was shown first) */
	isRefreshing: boolean;
	/** Error from last search */
	error: Error | null;
	/** Current page offset */
	offset: number;
	/** Load next page */
	loadMore: () => void;
	/** Whether there are more results */
	hasMore: boolean;
	/** Clear search results */
	clear: () => void;
	/** Manually trigger a search */
	search: (query: string) => Promise<void>;
	/** Where the current data came from */
	dataSource: DataSource | null;
	/** Cache statistics */
	cacheStats: { packageCount: number; searchCount: number } | null;
}

/** Internal state for results keyed to a query */
interface ResultState {
	query: string;
	packages: NixpkgsPackage[];
	total: number;
	offset: number;
	dataSource: DataSource | null;
	error: Error | null;
}

/**
 * Hook for searching nixpkgs packages via the agent API with IndexedDB caching.
 *
 * Shows cached/local results immediately while fetching fresh data.
 * Results are keyed to queries - changing the query immediately clears stale results.
 */
export function useNixpkgsSearch(
	options: UseNixpkgsSearchOptions = {},
): UseNixpkgsSearchReturn {
	const {
		host = "localhost",
		port = 9876,
		limit = 20,
		debounceMs = 300,
	} = options;

	// Input query (what user is typing)
	const [query, setQueryState] = useState("");

	// Results state - keyed to the query they belong to
	const [results, setResults] = useState<ResultState>({
		query: "",
		packages: [],
		total: 0,
		offset: 0,
		dataSource: null,
		error: null,
	});

	const [isLoading, setIsLoading] = useState(false);
	const [isRefreshing, setIsRefreshing] = useState(false);
	const [cacheStats, setCacheStats] = useState<{
		packageCount: number;
		searchCount: number;
	} | null>(null);

	const clientRef = useRef<AgentHttpClient | null>(null);
	const cacheRef = useRef(getNixpkgsCache());
	const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	const activeQueryRef = useRef<string>("");
	const abortControllerRef = useRef<AbortController | null>(null);

	// Get or create client
	const getClient = useCallback(() => {
		if (!clientRef.current) {
			const token = getStoredToken();
			clientRef.current = new AgentHttpClient(host, port, token ?? undefined);
		}
		return clientRef.current;
	}, [host, port]);

	// Update cache stats
	const updateCacheStats = useCallback(async () => {
		const stats = await cacheRef.current.getStats();
		setCacheStats({
			packageCount: stats.packageCount,
			searchCount: stats.searchCount,
		});
	}, []);

	// Set query and immediately clear results if query changed
	const setQuery = useCallback(
		(newQuery: string) => {
			const normalizedNew = newQuery.trim();
			const normalizedOld = query.trim();

			setQueryState(newQuery);

			// If query meaningfully changed, clear results immediately
			if (normalizedNew !== normalizedOld) {
				// Cancel any in-flight request
				abortControllerRef.current?.abort();
				abortControllerRef.current = null;

				// Clear results if new query doesn't match
				if (normalizedNew === "") {
					setResults({
						query: "",
						packages: [],
						total: 0,
						offset: 0,
						dataSource: null,
						error: null,
					});
					setIsLoading(false);
					setIsRefreshing(false);
				} else {
					// Set loading state immediately for new query
					setIsLoading(true);
					setIsRefreshing(false);
				}
			}
		},
		[query],
	);

	// Perform the search with caching
	const performSearch = useCallback(
		async (searchQuery: string, searchOffset: number, append: boolean) => {
			const normalizedQuery = searchQuery.trim();
			activeQueryRef.current = normalizedQuery;

			if (!normalizedQuery) {
				setResults({
					query: "",
					packages: [],
					total: 0,
					offset: 0,
					dataSource: null,
					error: null,
				});
				setIsLoading(false);
				setIsRefreshing(false);
				return;
			}

			const cache = cacheRef.current;

			// Create new abort controller for this request
			abortControllerRef.current?.abort();
			abortControllerRef.current = new AbortController();

			// For first page, try to show cached results immediately
			if (searchOffset === 0 && !append) {
				setIsLoading(true);

				// Step 1: Try cached search results
				const cached = await cache.getCachedSearch(normalizedQuery);

				// Check if query changed while checking cache
				if (activeQueryRef.current !== normalizedQuery) return;

				if (cached && cached.packages.length > 0) {
					setResults({
						query: normalizedQuery,
						packages: cached.packages.slice(0, limit),
						total: cached.total,
						offset: 0,
						dataSource: "cache",
						error: null,
					});
					setIsLoading(false);

					// If cache is fresh, we're done
					if (cached.isFresh) {
						setIsRefreshing(false);
						return;
					}

					// Otherwise, show cached but fetch fresh in background
					setIsRefreshing(true);
				} else {
					// Step 2: Try local search in package cache
					const localResults = await cache.searchLocal(normalizedQuery, limit);

					// Check if query changed while doing local search
					if (activeQueryRef.current !== normalizedQuery) return;

					if (localResults.length > 0) {
						setResults({
							query: normalizedQuery,
							packages: localResults,
							total: localResults.length,
							offset: 0,
							dataSource: "local",
							error: null,
						});
						setIsLoading(false);
						setIsRefreshing(true);
					}
				}
			}

			// Step 3: Fetch fresh data from API
			try {
				const client = getClient();
				const result = await client.searchNixpkgs({
					query: normalizedQuery,
					limit,
					offset: searchOffset,
				});

				// Check if query changed while we were fetching
				if (activeQueryRef.current !== normalizedQuery) {
					return;
				}

				// Update cache
				if (searchOffset === 0) {
					await cache.cacheSearchResults(
						normalizedQuery,
						result.packages,
						result.total,
					);
					await updateCacheStats();
				}

				// Update state
				setResults((prev) => {
					// Only update if this is still the active query
					if (activeQueryRef.current !== normalizedQuery) return prev;

					return {
						query: normalizedQuery,
						packages: append
							? [...prev.packages, ...result.packages]
							: result.packages,
						total: result.total,
						offset: searchOffset,
						dataSource: "fresh",
						error: null,
					};
				});
			} catch (err) {
				// Check if query changed or was aborted
				if (activeQueryRef.current !== normalizedQuery) {
					return;
				}

				// If we already have cached data, keep showing it
				setResults((prev) => {
					if (prev.query === normalizedQuery && prev.packages.length > 0) {
						// Keep cached data, just log the error
						console.warn("Failed to fetch fresh data, showing cached:", err);
						return prev;
					}
					// No cached data, show error
					return {
						query: normalizedQuery,
						packages: [],
						total: 0,
						offset: 0,
						dataSource: null,
						error: err instanceof Error ? err : new Error(String(err)),
					};
				});
			} finally {
				if (activeQueryRef.current === normalizedQuery) {
					setIsLoading(false);
					setIsRefreshing(false);
				}
			}
		},
		[limit, getClient, updateCacheStats],
	);

	// Debounced search when query changes
	useEffect(() => {
		if (debounceRef.current) {
			clearTimeout(debounceRef.current);
		}

		const normalizedQuery = query.trim();

		// For empty query, clear immediately
		if (!normalizedQuery) {
			performSearch("", 0, false);
			return;
		}

		debounceRef.current = setTimeout(() => {
			performSearch(query, 0, false);
		}, debounceMs);

		return () => {
			if (debounceRef.current) {
				clearTimeout(debounceRef.current);
			}
		};
	}, [query, debounceMs, performSearch]);

	// Load cache stats on mount
	useEffect(() => {
		updateCacheStats();
	}, [updateCacheStats]);

	// Load more results
	const loadMore = useCallback(() => {
		if (
			!isLoading &&
			!isRefreshing &&
			results.packages.length < results.total
		) {
			performSearch(query, results.offset + limit, true);
		}
	}, [
		isLoading,
		isRefreshing,
		results.packages.length,
		results.total,
		results.offset,
		query,
		limit,
		performSearch,
	]);

	// Clear results
	const clear = useCallback(() => {
		abortControllerRef.current?.abort();
		setQueryState("");
		setResults({
			query: "",
			packages: [],
			total: 0,
			offset: 0,
			dataSource: null,
			error: null,
		});
		setIsLoading(false);
		setIsRefreshing(false);
	}, []);

	// Manual search
	const search = useCallback(
		async (searchQuery: string) => {
			setQueryState(searchQuery);
			await performSearch(searchQuery, 0, false);
		},
		[performSearch],
	);

	// Memoize display values - only show results if they match the current query
	const displayValues = useMemo(() => {
		const normalizedQuery = query.trim();
		const matchingResults = results.query === normalizedQuery;

		const packages = matchingResults ? results.packages : [];
		const total = matchingResults ? results.total : 0;
		const error = matchingResults ? results.error : null;
		const dataSource = matchingResults ? results.dataSource : null;
		const offset = matchingResults ? results.offset : 0;
		const hasMore = packages.length < total;

		return { packages, total, error, dataSource, offset, hasMore };
	}, [query, results]);

	return useMemo(
		() => ({
			query,
			setQuery,
			packages: displayValues.packages,
			total: displayValues.total,
			isLoading,
			isRefreshing,
			error: displayValues.error,
			offset: displayValues.offset,
			loadMore,
			hasMore: displayValues.hasMore,
			clear,
			search,
			dataSource: displayValues.dataSource,
			cacheStats,
		}),
		[
			query,
			setQuery,
			displayValues,
			isLoading,
			isRefreshing,
			loadMore,
			clear,
			search,
			cacheStats,
		],
	);
}
