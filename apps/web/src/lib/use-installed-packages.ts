"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { type InstalledPackageInfo } from "./agent";
import { useAgentClient } from "./agent-provider";

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
  options: UseInstalledPackagesOptions = {},
): UseInstalledPackagesReturn {
  const { pollInterval = 0 } = options;
  const agentClient = useAgentClient();

  const [packages, setPackages] = useState<InstalledPackageInfo[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  // Fetch installed packages
  const fetchPackages = useCallback(async () => {
    try {
      setIsLoading(true);
      const client = agentClient;
      const pageSize = 100;
      let offset = 0;
      let total = 0;
      let allPackages: InstalledPackageInfo[] = [];

      while (true) {
        const result = await client.getInstalledPackages({
          limit: pageSize,
          offset,
        });

        if (offset === 0) {
          total = result.count ?? result.packages.length;
        }

        if (result.packages.length === 0) {
          break;
        }

        allPackages = [...allPackages, ...result.packages];
        offset += result.packages.length;

        if (allPackages.length >= total) {
          break;
        }
      }

      if (total === 0) {
        total = allPackages.length;
      }

      setPackages(allPackages);
      setTotalCount(total);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      setIsLoading(false);
    }
  }, [agentClient]);

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
    [installedSet],
  );

  return useMemo(
    () => ({
      packages,
      installedSet,
      count: totalCount,
      isLoading,
      error,
      refresh: fetchPackages,
      isInstalled,
    }),
    [
      packages,
      installedSet,
      totalCount,
      isLoading,
      error,
      fetchPackages,
      isInstalled,
    ],
  );
}
