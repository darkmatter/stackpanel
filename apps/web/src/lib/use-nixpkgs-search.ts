"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useAgentClient } from "./agent-provider";
import { getNixpkgsCache } from "./nixpkgs-cache";
import type { NixpkgsPackage } from "./types";

/** nixhub.io Remix data API - fast, no auth required */
const NIXHUB_SEARCH_API = "https://www.nixhub.io/search";

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

export type DataSource = "cache" | "fresh" | "local" | "nixhub";

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
  const { limit = 20, debounceMs = 300 } = options;
  const agentClient = useAgentClient();

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

  const cacheRef = useRef(getNixpkgsCache());
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const activeQueryRef = useRef<string>("");
  const abortControllerRef = useRef<AbortController | null>(null);

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

  // Search nixhub.io API (fast, no cache needed)
  const searchNixhub = useCallback(
    async (
      searchQuery: string,
      signal: AbortSignal,
    ): Promise<{ packages: NixpkgsPackage[]; total: number } | null> => {
      try {
        const url = `${NIXHUB_SEARCH_API}?q=${encodeURIComponent(searchQuery)}&_data=routes/_nixhub.search`;
        const response = await fetch(url, { signal });

        if (!response.ok) {
          return null;
        }

        const data: {
          query: string;
          total_results: number;
          results: Array<{ name: string; summary: string; last_updated: string }>;
        } = await response.json();

        const packages: NixpkgsPackage[] = data.results.map((r) => ({
          name: r.name,
          attr_path: r.name,
          version: "",
          description: r.summary || "",
        }));

        return { packages, total: data.total_results };
      } catch {
        return null;
      }
    },
    [],
  );

  // Perform the search - try nixhub first, fall back to agent with caching
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
      const abortController = new AbortController();
      abortControllerRef.current = abortController;

      setIsLoading(true);

      // Step 1: Try nixhub.io first (fast, no cache needed)
      // Only for first page - nixhub doesn't support pagination
      if (searchOffset === 0 && !append) {
        const nixhubResult = await searchNixhub(normalizedQuery, abortController.signal);

        if (activeQueryRef.current !== normalizedQuery) return;

        if (nixhubResult && nixhubResult.packages.length > 0) {
          setResults({
            query: normalizedQuery,
            packages: nixhubResult.packages.slice(0, limit),
            total: nixhubResult.total,
            offset: 0,
            dataSource: "nixhub",
            error: null,
          });
          setIsLoading(false);
          setIsRefreshing(false);
          return;
        }
      }

      // Step 2: Fallback - try cached results from agent API
      if (searchOffset === 0 && !append) {
        const cached = await cache.getCachedSearch(normalizedQuery);

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

          if (cached.isFresh) {
            setIsRefreshing(false);
            return;
          }

          setIsRefreshing(true);
        } else {
          // Try local search in package cache
          const localResults = await cache.searchLocal(normalizedQuery, limit);

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

      // Step 3: Fetch from agent API (supports pagination, slower)
      try {
        const client = agentClient;
        const result = await client.searchNixpkgs({
          query: normalizedQuery,
          limit,
          offset: searchOffset,
        });

        if (activeQueryRef.current !== normalizedQuery) {
          return;
        }

        // Update cache for agent results
        if (searchOffset === 0) {
          await cache.cacheSearchResults(
            normalizedQuery,
            result.packages,
            result.total,
          );
          await updateCacheStats();
        }

        setResults((prev) => {
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
        if (activeQueryRef.current !== normalizedQuery) {
          return;
        }

        // If we already have cached/nixhub data, keep showing it
        setResults((prev) => {
          if (prev.query === normalizedQuery && prev.packages.length > 0) {
            console.warn("Failed to fetch fresh data, showing cached:", err);
            return prev;
          }
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
    [limit, agentClient, updateCacheStats, searchNixhub],
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
