/**
 * Hook for fetching inspector data.
 *
 * Aggregates data from multiple sources:
 * - Generated files from stackpanel.files.entries
 * - Nix config (evaluated)
 * - Data entities from .stack/data/
 * - State files from .stack/state/
 * - Scripts/commands from devshell config
 */

import { useCallback, useEffect, useState } from "react";

// Enable debug logging with: localStorage.setItem('INSPECTOR_DEBUG', 'true')
const DEBUG = typeof window !== "undefined" && localStorage.getItem("INSPECTOR_DEBUG") === "true";

function debugLog(...args: unknown[]) {
  if (DEBUG) {
    console.log("[Inspector]", ...args);
  }
}
import { canonicalAgentOrigin, fetchWithAgentIdentity } from "./agent-identity";
import { useAgentContext } from "./agent-provider";
import type { GeneratedFilesResponse, GeneratedFileWithStatus } from "./types";

// =============================================================================
// Types
// =============================================================================

type QueryStatus = "idle" | "loading" | "success" | "error";

/** A script/command available in the devshell */
export interface InspectorScript {
  name: string;
  command: string;
  description?: string;
  source: "scripts" | "commands" | "_scripts" | "_tasks" | "motd";
  /** Path to the script executable (if found) */
  scriptPath?: string;
  /** Source code of the script (if readable) */
  scriptSource?: string;
  /** Whether the script is a binary (source not readable) */
  isBinary?: boolean;
}

/** A data entity file in .stack/data/ */
export interface InspectorDataFile {
  name: string;
  path: string;
  data: unknown;
}

/** A state file in .stack/state/ */
export interface InspectorStateFile {
  name: string;
  path: string;
  content: string;
  exists: boolean;
}

/** Generated file with additional inspector metadata */
export interface InspectorGeneratedFile extends GeneratedFileWithStatus {
  /** Relative path for display */
  relativePath: string;
}


/** Complete inspector data */
export interface InspectorData {
  /** Project information */
  project: {
    name: string;
    path: string;
    github?: string;
  } | null;

  /** Generated files */
  generatedFiles: {
    files: InspectorGeneratedFile[];
    totalCount: number;
    staleCount: number;
    enabledCount: number;
    lastUpdated: string;
  };

  /** Full Nix config (evaluated) */
  config: Record<string, unknown> | null;

  /** Source of the config (e.g., "flake_watcher", "legacy_cache", "fresh_eval") */
  configSource: string | null;

  /** Custom scripts available in PATH */
  scripts: InspectorScript[];

  /** Data entity files */
  dataFiles: InspectorDataFile[];

  /** State files */
  stateFiles: InspectorStateFile[];

  /** Directories info */
  directories: {
    home: string;
    data: string;
    gen: string;
    state: string;
    secrets: string;
  } | null;

}

interface UseInspectorDataState {
  data: InspectorData | null;
  error: Error | null;
  status: QueryStatus;
  isLoading: boolean;
  isError: boolean;
  isSuccess: boolean;
  dataUpdatedAt: number | null;
}

interface UseInspectorDataOptions {
  /** Whether to fetch on mount */
  enabled?: boolean;
}

interface UseInspectorDataResult extends UseInspectorDataState {
  /** Re-fetch all inspector data */
  refetch: () => Promise<void>;
  /** Refresh just the config */
  refreshConfig: () => Promise<void>;
}

// =============================================================================
// Helpers
// =============================================================================

function fetchInspectorResource(
  origin: string,
  token: string | null,
  url: string,
): Promise<Response> {
  if (!token) throw new Error("Agent authentication required");
  return fetchWithAgentIdentity(origin, token, url, { headers: { "X-Stackpanel-Token": token } });
}

// =============================================================================
// Hook
// =============================================================================

export function useInspectorData(options: UseInspectorDataOptions = {}): UseInspectorDataResult {
  const { enabled = true } = options;
  const { host, port, token, projectRoot } = useAgentContext();

  const baseUrl = canonicalAgentOrigin(host, port);

  const [state, setState] = useState<UseInspectorDataState>({
    data: null,
    error: null,
    status: "loading",
    isLoading: true,
    isError: false,
    isSuccess: false,
    dataUpdatedAt: null,
  });

  const fetchData = useCallback(async () => {
    debugLog("fetchData called, baseUrl:", baseUrl, "token:", token ? "set" : "not set");

    setState((prev) => ({
      ...prev,
      status: "loading",
      isLoading: true,
      error: null,
    }));

    try {
      // Fetch all data in parallel
      const [generatedFilesRes, configRes, entitiesRes, stateFilesRes] = await Promise.all([
        fetchGeneratedFiles(baseUrl, token),
        fetchConfig(baseUrl, token),
        fetchDataEntities(baseUrl, token),
        fetchStateFiles(baseUrl, token),
      ]);

      // Extract scripts from config and fetch their sources
      const extractedScripts = extractScripts(configRes.config);
      const scripts = await fetchScriptSources(baseUrl, token, extractedScripts);

      // Derive directories from project root
      const stackpanelHome = projectRoot ? `${projectRoot}/.stack` : null;
      const directories = stackpanelHome
        ? {
            home: stackpanelHome,
            data: `${stackpanelHome}/data`,
            gen: `${stackpanelHome}/gen`,
            state: `${stackpanelHome}/state`,
            secrets: `${stackpanelHome}/secrets`,
          }
        : null;

      // Build the inspector data
      const filesWithRelative = generatedFilesRes.files.map((f) => ({
        ...f,
        relativePath: f.path,
      }));
      const data: InspectorData = {
        project: projectRoot
          ? {
              name: projectRoot.split("/").pop() ?? "Unknown",
              path: projectRoot,
            }
          : null,
        generatedFiles: {
          files: filesWithRelative,
          totalCount: generatedFilesRes.totalCount,
          staleCount: generatedFilesRes.staleCount,
          enabledCount: generatedFilesRes.enabledCount,
          lastUpdated: generatedFilesRes.lastUpdated,
        },
        config: configRes.config,
        configSource: configRes.source,
        scripts,
        dataFiles: entitiesRes,
        stateFiles: stateFilesRes,
        directories,
      };

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
  }, [baseUrl, token, projectRoot]);

  const refreshConfig = useCallback(async () => {
    try {
      const configRes = await fetchConfig(baseUrl, token, true);
      setState((prev) => {
        if (!prev.data) return prev;
        const scripts = extractScripts(configRes.config);
        return {
          ...prev,
          data: {
            ...prev.data,
            config: configRes.config,
            configSource: configRes.source,
            scripts,
          },
          dataUpdatedAt: Date.now(),
        };
      });
    } catch (err) {
      console.error("Failed to refresh config:", err);
    }
  }, [baseUrl, token]);

  // Fetch on mount if enabled
  useEffect(() => {
    if (enabled) {
      fetchData();
    }
  }, [enabled, fetchData]);

  return {
    ...state,
    refetch: fetchData,
    refreshConfig,
  };
}

// =============================================================================
// Data Fetching Helpers
// =============================================================================

async function fetchGeneratedFiles(
  baseUrl: string,
  token: string | null,
): Promise<GeneratedFilesResponse> {
  try {
    debugLog("Fetching generated files from:", `${baseUrl}/api/nix/files`);
    const res = await fetchInspectorResource(baseUrl, token, `${baseUrl}/api/nix/files`);
    const data = await res.json();
    debugLog("Generated files response:", data);
    if (!data.success) {
      debugLog("Generated files API returned success=false:", data.error);
      return {
        files: [],
        totalCount: 0,
        staleCount: 0,
        enabledCount: 0,
        lastUpdated: new Date().toISOString(),
      };
    }
    debugLog("Generated files count:", data.data?.files?.length ?? 0);
    return data.data;
  } catch (err) {
    debugLog("Failed to fetch generated files:", err);
    return {
      files: [],
      totalCount: 0,
      staleCount: 0,
      enabledCount: 0,
      lastUpdated: new Date().toISOString(),
    };
  }
}

interface ConfigResult {
  config: Record<string, unknown> | null;
  source: string | null;
}

async function fetchConfig(
  baseUrl: string,
  token: string | null,
  refresh = false,
): Promise<ConfigResult> {
  try {
    const url = refresh ? `${baseUrl}/api/nix/config?refresh=true` : `${baseUrl}/api/nix/config`;
    debugLog("Fetching config from:", url);
    const res = await fetchInspectorResource(baseUrl, token, url);
    const data = await res.json();
    debugLog("Config response:", data);
    if (!data.success) {
      debugLog("Config API returned success=false:", data.error);
      return { config: null, source: null };
    }
    debugLog("Config loaded, keys:", Object.keys(data.data?.config ?? {}));
    return {
      config: data.data?.config ?? null,
      source: data.data?.source ?? null,
    };
  } catch (err) {
    debugLog("Failed to fetch config:", err);
    return { config: null, source: null };
  }
}

async function fetchDataEntities(
  baseUrl: string,
  token: string | null,
): Promise<InspectorDataFile[]> {
  try {
    debugLog("Fetching data entities from:", `${baseUrl}/api/nix/data/list`);
    const res = await fetchInspectorResource(baseUrl, token, `${baseUrl}/api/nix/data/list`);
    const data = await res.json();
    debugLog("Data entities response:", data);
    if (!data.success || !data.data?.entities) {
      debugLog("Data entities API returned empty or failed");
      return [];
    }

    const entities: InspectorDataFile[] = [];
    for (const entityName of data.data.entities) {
      try {
        const entityRes = await fetchInspectorResource(
          baseUrl,
          token,
          `${baseUrl}/api/nix/data?entity=${encodeURIComponent(entityName)}`,
        );
        const entityData = await entityRes.json();
        if (entityData.success && entityData.data?.exists) {
          entities.push({
            name: entityName,
            path: `.stack/data/${entityName}.nix`,
            data: entityData.data.data,
          });
        }
      } catch {
        // Skip entities that fail to load
      }
    }
    return entities;
  } catch {
    return [];
  }
}

async function fetchStateFiles(
  baseUrl: string,
  token: string | null,
): Promise<InspectorStateFile[]> {
  debugLog("Fetching state files...");
  const stateFiles: InspectorStateFile[] = [];

  // List all files in .stack/state/
  try {
    const listRes = await fetchInspectorResource(
      baseUrl,
      token,
      `${baseUrl}/api/files/list?path=${encodeURIComponent(".stack/state")}`,
    );
    const listData = await listRes.json();
    if (!listData.success || !listData.data?.exists || !listData.data?.files) {
      debugLog("State directory doesn't exist or is empty");
      return [];
    }

    // Get file names (exclude directories)
    const files = listData.data.files.filter((f: { name: string; isDir: boolean }) => !f.isDir);
    debugLog(
      "Found state files:",
      files.map((f: { name: string }) => f.name),
    );

    // Fetch content for each file
    for (const file of files) {
      try {
        const res = await fetchInspectorResource(
          baseUrl,
          token,
          `${baseUrl}/api/files?path=${encodeURIComponent(`.stack/state/${file.name}`)}`,
        );
        const data = await res.json();
        if (data.success && data.data?.exists) {
          stateFiles.push({
            name: file.name,
            path: `.stack/state/${file.name}`,
            content: data.data.content ?? "",
            exists: true,
          });
        }
      } catch {
        // Skip files that fail to load
      }
    }
  } catch {
    debugLog("Failed to list state directory");
  }

  return stateFiles;
}

async function fetchScriptSources(
  baseUrl: string,
  token: string | null,
  scripts: InspectorScript[],
): Promise<InspectorScript[]> {
  debugLog("Fetching script sources for", scripts.length, "scripts");

  // Fetch sources in parallel (limit concurrency to avoid overwhelming the server)
  const results = await Promise.all(
    scripts.map(async (script) => {
      try {
        const res = await fetchInspectorResource(
          baseUrl,
          token,
          `${baseUrl}/api/scripts/source?name=${encodeURIComponent(script.name)}`,
        );
        const data = await res.json();
        if (data.success && data.data?.found) {
          return {
            ...script,
            scriptPath: data.data.path,
            scriptSource: data.data.isBinary ? undefined : data.data.source,
            isBinary: data.data.isBinary,
          };
        }
      } catch {
        // Skip scripts that fail to fetch
      }
      return script;
    }),
  );

  return results;
}

// =============================================================================
// Extraction Helpers
// =============================================================================

/** A file may have a producer which is not registered as a Studio module. */
export function inspectorContributors(
  modules: Iterable<{ id: string; name: string }>,
  files: readonly Pick<InspectorGeneratedFile, "source">[],
) {
  const labels = new Map<string, string>();
  for (const { id, name } of modules) labels.set(id, name);
  for (const { source } of files) {
    if (source && !labels.has(source)) labels.set(source, source);
  }
  return Array.from(labels, ([id, label]) => ({ id, label })).sort((a, b) =>
    a.label.localeCompare(b.label),
  );
}

function extractScripts(config: Record<string, unknown> | null): InspectorScript[] {
  if (!config) return [];

  const scripts: InspectorScript[] = [];
  const seen = new Set<string>();

  // Get stackpanel config
  const stackpanel = (config as Record<string, unknown>)?.stackpanel ?? config;
  const devshell =
    (stackpanel as Record<string, unknown>)?.devshell ?? ({} as Record<string, unknown>);
  const motd = (stackpanel as Record<string, unknown>)?.motd ?? ({} as Record<string, unknown>);

  // Extract from motd.commands (array format: { name, description })
  const motdCommands = (motd as Record<string, unknown>)?.commands;
  if (Array.isArray(motdCommands)) {
    for (const cmd of motdCommands) {
      if (cmd && typeof cmd === "object") {
        const name = (cmd as Record<string, unknown>).name as string;
        const description = (cmd as Record<string, unknown>).description as string | undefined;
        if (name && !seen.has(name)) {
          seen.add(name);
          scripts.push({ name, command: name, description, source: "motd" });
        }
      }
    }
  }

  // Sources to check for scripts (object format: { [name]: { exec, command, description } })
  const sources: Array<{
    data: Record<string, unknown> | undefined;
    source: InspectorScript["source"];
  }> = [
    {
      data: (stackpanel as Record<string, unknown>)?.scripts as Record<string, unknown> | undefined,
      source: "scripts",
    },
    {
      data: (stackpanel as Record<string, unknown>)?.commands as
        | Record<string, unknown>
        | undefined,
      source: "commands",
    },
    {
      data: (devshell as Record<string, unknown>)?.commands as Record<string, unknown> | undefined,
      source: "commands",
    },
    {
      data: (devshell as Record<string, unknown>)?._scripts as Record<string, unknown> | undefined,
      source: "_scripts",
    },
    {
      data: (devshell as Record<string, unknown>)?._tasks as Record<string, unknown> | undefined,
      source: "_tasks",
    },
  ];

  for (const { data, source } of sources) {
    if (!data || typeof data !== "object") continue;

    for (const [name, value] of Object.entries(data)) {
      if (seen.has(name)) continue;
      seen.add(name);

      let command = "";
      let description: string | undefined;
      if (typeof value === "string") {
        command = value;
      } else if (value && typeof value === "object") {
        const v = value as Record<string, unknown>;
        command = ((v.exec ?? v.command ?? "") as string) || "";
        description = (v.description as string) || undefined;
      }

      scripts.push({ name, command, description, source });
    }
  }

  return scripts;
}
