/**
 * Hook for fetching process sources from various origins:
 * - Apps (from useApps hook)
 * - Scripts (from Nix config)
 * - Tasks (from Turbo query)
 * - Custom (user-defined, stored in local state)
 */

import { useMemo } from "react";
import { useApps, useNixConfigQuery, useTurboPackages, useProcesses } from "@/lib/use-agent";
import type { ProcessSource, ProcessStatus, ProcessComposeSettings } from "../types";

// =============================================================================
// Types for Nix Config Data
// =============================================================================

interface NixScriptConfig {
  exec?: string;
  path?: string;
  description?: string;
}

interface NixProcessComposeConfig {
  enable?: boolean;
  commandName?: string;
  formatWatcher?: {
    enable?: boolean;
    extensions?: string[];
    command?: string;
  };
  processes?: Record<string, unknown>;
  environment?: Record<string, string>;
}

// =============================================================================
// Hook: useProcessSources
// =============================================================================

/** Service config shape from Nix */
interface NixServiceConfig {
  enable?: boolean;
  displayName?: string;
  description?: string;
  command?: string;
  port?: number;
  autoStart?: boolean;
  dataDir?: string;
}

export interface UseProcessSourcesResult {
  /** Apps available as process sources */
  appSources: ProcessSource[];
  /** Services available as process sources */
  serviceSources: ProcessSource[];
  /** Scripts available as process sources */
  scriptSources: ProcessSource[];
  /** Tasks available as process sources */
  taskSources: ProcessSource[];
  /** Current process-compose settings from Nix config */
  settings: ProcessComposeSettings;
  /** Live process statuses */
  statuses: Record<string, ProcessStatus>;
  /** Loading state */
  isLoading: boolean;
  /** Error state */
  error: Error | null;
  /** Refetch data */
  refetch: () => void;
}

export function useProcessSources(): UseProcessSourcesResult {
  // Fetch apps from the dedicated hook
  const appsQuery = useApps();
  
  // Fetch Nix config for scripts and process-compose settings
  const nixConfigQuery = useNixConfigQuery();
  
  // Fetch turbo packages for tasks
  const turboQuery = useTurboPackages();
  
  // Fetch live process status
  const processesQuery = useProcesses();

  // Extract apps from useApps hook
  const appSources = useMemo<ProcessSource[]>(() => {
    const apps = appsQuery.data;
    if (!apps || typeof apps !== 'object') return [];

    return Object.entries(apps).map(([name, app]) => {
      // App type from proto
      const appData = app as {
        name?: string;
        path?: string;
        port?: number;
        type?: string;
        tasks?: Record<string, { command?: string }>;
      };
      
      // Use turbo run by default, or a specific command if tasks.dev exists
      const devTask = appData.tasks?.dev;
      const defaultCommand = `turbo run -F ${name} dev`;
      const command = devTask?.command ?? defaultCommand;
      
      return {
        id: `app-${name}`,
        type: "app" as const,
        name: appData.name ?? name,
        command,
        workingDir: appData.path,
        enabled: true, // Apps enabled by default
        autoStart: true, // Apps auto-start by default
        useEntrypoint: true, // Use entrypoint scripts by default (handles env/secrets)
        namespace: "apps",
        appName: name,
      };
    });
  }, [appsQuery.data]);

  // Extract scripts from Nix config
  const scriptSources = useMemo<ProcessSource[]>(() => {
    const config = nixConfigQuery.data?.config;
    if (!config) return [];

    // Try to find scripts in the config - check multiple possible locations
    let scriptsConfig: Record<string, NixScriptConfig> | undefined;
    
    // Check if scripts is at root level
    if ((config as Record<string, unknown>).scripts) {
      scriptsConfig = (config as Record<string, unknown>).scripts as Record<string, NixScriptConfig>;
    }
    // Check if it's under stackpanel
    else if ((config as Record<string, unknown>)?.stackpanel) {
      const stackpanel = (config as Record<string, unknown>).stackpanel as Record<string, unknown>;
      scriptsConfig = stackpanel?.scripts as Record<string, NixScriptConfig>;
    }
    
    if (!scriptsConfig) return [];

    return Object.entries(scriptsConfig).map(([name, script]) => ({
      id: `script-${name}`,
      type: "script" as const,
      name,
      command: script.exec ?? name,
      enabled: false, // Scripts disabled by default, user opts in
      autoStart: true, // Scripts auto-start when enabled
      useEntrypoint: false, // Scripts don't use entrypoints by default
      namespace: "scripts",
      scriptName: name,
      description: script.description,
    }));
  }, [nixConfigQuery.data]);

  // Extract services from Nix config
  const serviceSources = useMemo<ProcessSource[]>(() => {
    const config = nixConfigQuery.data?.config;
    if (!config) return [];

    // Try to find services in the config - check multiple possible locations
    let servicesConfig: Record<string, NixServiceConfig> | undefined;

    if ((config as Record<string, unknown>).services) {
      servicesConfig = (config as Record<string, unknown>).services as Record<string, NixServiceConfig>;
    } else if ((config as Record<string, unknown>)?.stackpanel) {
      const stackpanel = (config as Record<string, unknown>).stackpanel as Record<string, unknown>;
      servicesConfig = stackpanel?.services as Record<string, NixServiceConfig>;
    }

    if (!servicesConfig || typeof servicesConfig !== "object") return [];

    return Object.entries(servicesConfig)
      .filter(([_, svc]) => svc && svc.enable === true)
      .map(([name, svc]) => ({
        id: `service-${name}`,
        type: "service" as const,
        name: svc.displayName ?? name,
        command: svc.command ?? "",
        enabled: true, // Services enabled by default when defined
        autoStart: svc.autoStart !== false,
        useEntrypoint: false, // Services don't use entrypoints
        namespace: "services",
        port: svc.port,
        dataDir: svc.dataDir,
        displayName: svc.displayName ?? name,
        description: svc.description,
      }));
  }, [nixConfigQuery.data]);

  // Extract tasks from Turbo packages
  const taskSources = useMemo<ProcessSource[]>(() => {
    const { packages } = turboQuery;
    if (!packages || packages.length === 0) return [];

    const sources: ProcessSource[] = [];

    for (const pkg of packages) {
      // Skip root package
      if (pkg.name === "//" || pkg.name === "root") continue;

      for (const task of pkg.tasks) {
        sources.push({
          id: `task-${pkg.name}-${task.name}`,
          type: "task" as const,
          name: `${pkg.name}:${task.name}`,
          command: `turbo run -F ${pkg.name} ${task.name}`,
          workingDir: pkg.path,
          enabled: false, // Tasks disabled by default
          autoStart: true, // Tasks auto-start when enabled
          useEntrypoint: false, // Tasks don't use entrypoints by default
          namespace: "tasks",
          taskName: task.name,
          packageFilter: pkg.name,
        });
      }
    }

    return sources;
  }, [turboQuery.packages]);

  // Extract current process-compose settings from Nix config
  const settings = useMemo<ProcessComposeSettings>(() => {
    const config = nixConfigQuery.data?.config;
    const defaultSettings: ProcessComposeSettings = {
      enable: true,
      commandName: "dev",
      formatWatcher: {
        enable: true,
        extensions: ["ts", "tsx", "js", "jsx", "json", "md", "css", "scss", "html", "nix", "go", "rs", "py"],
      },
      environment: {},
    };
    
    if (!config) return defaultSettings;

    // Try to find process-compose config
    let pcConfig: NixProcessComposeConfig | undefined;
    
    if ((config as Record<string, unknown>)["process-compose"]) {
      pcConfig = (config as Record<string, unknown>)["process-compose"] as NixProcessComposeConfig;
    } else if ((config as Record<string, unknown>)?.stackpanel) {
      const stackpanel = (config as Record<string, unknown>).stackpanel as Record<string, unknown>;
      pcConfig = stackpanel?.["process-compose"] as NixProcessComposeConfig;
    }

    if (!pcConfig) return defaultSettings;

    return {
      enable: pcConfig.enable !== false,
      commandName: pcConfig.commandName ?? "dev",
      formatWatcher: {
        enable: pcConfig.formatWatcher?.enable !== false,
        extensions: pcConfig.formatWatcher?.extensions ?? defaultSettings.formatWatcher.extensions,
        command: pcConfig.formatWatcher?.command,
      },
      environment: pcConfig.environment ?? {},
    };
  }, [nixConfigQuery.data]);

  // Map live process status
  const statuses = useMemo<Record<string, ProcessStatus>>(() => {
    const processes = processesQuery.data?.processes;
    if (!processes) return {};

    const statusMap: Record<string, ProcessStatus> = {};
    
    for (const proc of processes) {
      statusMap[proc.name] = {
        name: proc.name,
        namespace: proc.namespace,
        status: proc.status as ProcessStatus["status"],
        isRunning: proc.isRunning,
        pid: proc.pid,
        exitCode: proc.exitCode,
        restarts: proc.restarts,
        systemTime: proc.systemTime,
      };
    }

    return statusMap;
  }, [processesQuery.data]);

  // Combined loading state
  const isLoading = appsQuery.isLoading || nixConfigQuery.isLoading || turboQuery.isLoading || processesQuery.isLoading;
  
  // Combined error
  const error = appsQuery.error ?? nixConfigQuery.error ?? turboQuery.error ?? processesQuery.error ?? null;

  // Refetch all data
  const refetch = () => {
    appsQuery.refetch();
    nixConfigQuery.refetch();
    turboQuery.refetch();
    processesQuery.refetch();
  };

  return {
    appSources,
    serviceSources,
    scriptSources,
    taskSources,
    settings,
    statuses,
    isLoading,
    error,
    refetch,
  };
}
