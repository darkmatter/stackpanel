import { useCallback, useEffect, useState } from "react";
import type { GeneratedFilesResponse, GeneratedFileWithStatus } from "./types";
import { useAgentClient } from "./agent-provider";

// =============================================================================
// Types
// =============================================================================

type QueryStatus = "idle" | "loading" | "success" | "error";

interface UseGeneratedFilesState {
  data: GeneratedFilesResponse | null;
  error: Error | null;
  status: QueryStatus;
  isLoading: boolean;
  isError: boolean;
  isSuccess: boolean;
  dataUpdatedAt: number | null;
}

interface UseGeneratedFilesOptions {
  /** Auth token (defaults to localStorage) */
  token?: string;
  /** Base URL for the agent (defaults to localhost:9876) */
  baseUrl?: string;
  /** Whether to fetch on mount (default: true) */
  enabled?: boolean;
}

interface UseGeneratedFilesResult extends UseGeneratedFilesState {
  /** Re-fetch the generated files */
  refetch: () => Promise<void>;
  /** Files grouped by source module */
  filesBySource: Record<string, GeneratedFileWithStatus[]>;
  /** Get files for a specific source */
  getFilesBySource: (source: string) => GeneratedFileWithStatus[];
  /** Get stale files only */
  staleFiles: GeneratedFileWithStatus[];
  /** Get enabled files only */
  enabledFiles: GeneratedFileWithStatus[];
}

// =============================================================================
// Helpers
// =============================================================================

const STORAGE_KEY = "stackpanel.agent.token";

function getStoredToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(STORAGE_KEY);
}

function groupFilesBySource(
  files: GeneratedFileWithStatus[],
): Record<string, GeneratedFileWithStatus[]> {
  const result: Record<string, GeneratedFileWithStatus[]> = {};

  for (const file of files) {
    const source = file.source ?? "unknown";
    if (!result[source]) {
      result[source] = [];
    }
    result[source].push(file);
  }

  // Sort files within each group by path
  for (const source of Object.keys(result)) {
    result[source].sort((a, b) => a.path.localeCompare(b.path));
  }

  return result;
}

// =============================================================================
// Hook
// =============================================================================

/**
 * Hook to fetch and manage generated files metadata.
 *
 * @example
 * ```tsx
 * function FilesPanel() {
 *   const {
 *     data,
 *     isLoading,
 *     filesBySource,
 *     staleFiles,
 *     refetch
 *   } = useGeneratedFiles();
 *
 *   if (isLoading) return <Spinner />;
 *
 *   return (
 *     <div>
 *       <p>{data?.totalCount} files, {data?.staleCount} stale</p>
 *       {Object.entries(filesBySource).map(([source, files]) => (
 *         <div key={source}>
 *           <h3>{source}</h3>
 *           {files.map(f => <FileRow key={f.path} file={f} />)}
 *         </div>
 *       ))}
 *     </div>
 *   );
 * }
 * ```
 */
export function useGeneratedFiles(
  options: UseGeneratedFilesOptions = {},
): UseGeneratedFilesResult {
  const { token: optionToken, enabled = true } = options;

  const storedToken = getStoredToken();
  const token = optionToken ?? storedToken;

  const client = useAgentClient();
  // Ensure token is set on the client when provided
  useEffect(() => {
    if (token) client.setToken(token);
  }, [token, client]);

  const [state, setState] = useState<UseGeneratedFilesState>({
    data: null,
    error: null,
    status: "idle",
    isLoading: false,
    isError: false,
    isSuccess: false,
    dataUpdatedAt: null,
  });

  const fetchFiles = useCallback(async () => {
    if (!client) return;
    setState((prev) => ({
      ...prev,
      status: "loading",
      isLoading: true,
      error: null,
    }));

    try {
      // Use the helper that handles the { success, data } wrapper
      const response = await client.getGeneratedFiles();

      setState({
        data: response,
        error: null,
        status: "success",
        isLoading: false,
        isError: false,
        isSuccess: true,
        dataUpdatedAt: Date.now(),
      });
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));

      setState((prev) => ({
        ...prev,
        error,
        status: "error",
        isLoading: false,
        isError: true,
        isSuccess: false,
      }));
    }
  }, [client]);

  // Fetch on mount if enabled
  useEffect(() => {
    if (enabled) {
      fetchFiles();
    }
  }, [enabled, fetchFiles]);

  // Computed values
  const files = state.data?.files ?? [];
  const filesBySource = groupFilesBySource(files);
  const staleFiles = files.filter((f) => f.isStale && f.enable);
  const enabledFiles = files.filter((f) => f.enable);

  const getFilesBySource = useCallback(
    (source: string): GeneratedFileWithStatus[] => {
      return filesBySource[source] ?? [];
    },
    [filesBySource],
  );

  return {
    ...state,
    refetch: fetchFiles,
    filesBySource,
    getFilesBySource,
    staleFiles,
    enabledFiles,
  };
}

// =============================================================================
// Utility Hooks
// =============================================================================

/**
 * Hook to get just the stale files count.
 * Useful for badges/indicators.
 */
export function useStaleFilesCount(options: UseGeneratedFilesOptions = {}): {
  count: number;
  isLoading: boolean;
} {
  const { data, isLoading } = useGeneratedFiles(options);

  return {
    count: data?.staleCount ?? 0,
    isLoading,
  };
}

/**
 * Hook to check if a specific file is stale.
 */
export function useFileStatus(
  path: string,
  options: UseGeneratedFilesOptions = {},
): {
  file: GeneratedFileWithStatus | null;
  isStale: boolean;
  isLoading: boolean;
} {
  const { data, isLoading } = useGeneratedFiles(options);

  const file = data?.files.find((f) => f.path === path) ?? null;

  return {
    file,
    isStale: file?.isStale ?? false,
    isLoading,
  };
}
