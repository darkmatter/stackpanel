"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AgentHttpClient, type InstalledPackageInfo } from "./agent";

const STORAGE_KEY = "stackpanel.agent.token";

function getStoredToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(STORAGE_KEY);
}

export interface UseInstalledPackagesOptions {
  /** Agent host */
  host?: string;
  /** Agent port */
  port?: number;
  /** Polling interval in ms (0 to disable) */
  pollInterval?: number;
}

export interface UseInstalledPackagesReturn {
  /** List of installed packages */
  packages: InstalledPackageInfo[];
  /** Set of installed package names (lowercase) for fast lookup */
  installedSet: Set<string>;
  /** Number of installed packages */
  count: number;
  /** Whether the data is loading */
  isLoading: boolean;
  /** Error if any */
  error: Error | null;
  /** Refresh the installed packages list */
  refresh: () => Promise<void>;
  /** Check if a package name is installed */
  isInstalled: (name: string) => boolean;
}

/**
 * Hook for fetching installed packages from the devenv/stackpanel config.
 * Can be used across multiple screens to show installed status.
 *
 * @example
 * ```tsx
 * function PackageList() {
 *   const { packages, isInstalled, isLoading } = useInstalledPackages();
 *
 *   return (
 *     <ul>
 *       {packages.map((pkg) => (
 *         <li key={pkg.name}>
 *           {pkg.name} - {pkg.version}
 *         </li>
 *       ))}
 *     </ul>
 *   );
 * }
 * ```
 */
export function useInstalledPackages(
  options: UseInstalledPackagesOptions = {}
): UseInstalledPackagesReturn {
  const { host = "localhost", port = 9876, pollInterval = 0 } = options;

  const [packages, setPackages] = useState<InstalledPackageInfo[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const clientRef = useRef<AgentHttpClient | null>(null);

  // Get or create client
  const getClient = useCallback(() => {
    if (!clientRef.current) {
      const token = getStoredToken();
      clientRef.current = new AgentHttpClient(host, port, token ?? undefined);
    }
    return clientRef.current;
  }, [host, port]);

  // Fetch installed packages
  const fetchPackages = useCallback(async () => {
    try {
      const client = getClient();
      const result = await client.getInstalledPackages();
      setPackages(result.packages);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      setIsLoading(false);
    }
  }, [getClient]);

  // Initial fetch
  useEffect(() => {
    fetchPackages();
  }, [fetchPackages]);

  // Optional polling
  useEffect(() => {
    if (pollInterval <= 0) return;

    const interval = setInterval(fetchPackages, pollInterval);
    return () => clearInterval(interval);
  }, [pollInterval, fetchPackages]);

  // Build installed set for fast lookup
  const installedSet = useMemo(() => {
    const set = new Set<string>();
    for (const pkg of packages) {
      if (pkg.name) set.add(pkg.name.toLowerCase());
      if (pkg.attrPath) set.add(pkg.attrPath.toLowerCase());
    }
    return set;
  }, [packages]);

  // Check if a package is installed
  const isInstalled = useCallback(
    (name: string): boolean => {
      return installedSet.has(name.toLowerCase());
    },
    [installedSet]
  );

  return useMemo(
    () => ({
      packages,
      installedSet,
      count: packages.length,
      isLoading,
      error,
      refresh: fetchPackages,
      isInstalled,
    }),
    [packages, installedSet, isLoading, error, fetchPackages, isInstalled]
  );
}
