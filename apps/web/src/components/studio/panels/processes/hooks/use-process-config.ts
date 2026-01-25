/**
 * Hook for managing process-compose configuration state and generating output.
 *
 * Handles:
 * - Merging sources with local customizations
 * - Custom process management
 * - Nix expression generation
 * - YAML preview generation
 */

import { useState, useCallback, useMemo } from "react";
import type {
  ProcessSource,
  ProcessComposeSettings,
  ProcessConfig,
  ProcessComposeYamlConfig,
  SourceTab,
  GeneratedNixConfig,
  NixOutputFormat,
} from "../types";
import { DEFAULT_SETTINGS } from "../types";

// =============================================================================
// Types
// =============================================================================

export interface UseProcessConfigOptions {
  /** Initial sources from useProcessSources */
  initialSources?: ProcessSource[];
  /** Initial settings from useProcessSources */
  initialSettings?: ProcessComposeSettings;
}

export interface UseProcessConfigResult {
  /** All process sources (merged with local state) */
  sources: ProcessSource[];
  /** Custom processes added by user */
  customSources: ProcessSource[];
  /** Current settings */
  settings: ProcessComposeSettings;
  /** Currently active source tab */
  activeTab: SourceTab;
  /** Search query */
  searchQuery: string;

  // Actions
  /** Set active tab */
  setActiveTab: (tab: SourceTab) => void;
  /** Set search query */
  setSearchQuery: (query: string) => void;
  /** Toggle a source on/off */
  toggleSource: (id: string, enabled: boolean) => void;
  /** Toggle auto-start for a source */
  toggleAutoStart: (id: string, autoStart: boolean) => void;
  /** Toggle entrypoint usage for a source */
  toggleEntrypoint: (id: string, useEntrypoint: boolean) => void;
  /** Update settings */
  updateSettings: (settings: Partial<ProcessComposeSettings>) => void;
  /** Add a custom process */
  addCustomSource: (source: Omit<ProcessSource, "id" | "type">) => void;
  /** Remove a custom process */
  removeCustomSource: (id: string) => void;
  /** Update a custom process */
  updateCustomSource: (id: string, updates: Partial<ProcessSource>) => void;

  // Generators
  /** Generate Nix expression */
  generateNix: (format?: NixOutputFormat) => GeneratedNixConfig;
  /** Generate YAML preview */
  generateYaml: () => string;
  /** Get enabled sources only */
  getEnabledSources: () => ProcessSource[];
}

// =============================================================================
// Hook Implementation
// =============================================================================

export function useProcessConfig(
  options: UseProcessConfigOptions = {}
): UseProcessConfigResult {
  const { initialSources = [], initialSettings } = options;

  // Local state for source overrides (enabled/disabled)
  const [sourceOverrides, setSourceOverrides] = useState<Record<string, boolean>>({});
  
  // Local state for autoStart overrides
  const [autoStartOverrides, setAutoStartOverrides] = useState<Record<string, boolean>>({});
  
  // Local state for entrypoint overrides
  const [entrypointOverrides, setEntrypointOverrides] = useState<Record<string, boolean>>({});
  
  // Local state for custom processes
  const [customSources, setCustomSources] = useState<ProcessSource[]>([]);
  
  // Settings state (starts from initial or defaults)
  const [settings, setSettings] = useState<ProcessComposeSettings>(
    initialSettings ?? DEFAULT_SETTINGS
  );
  
  // UI state
  const [activeTab, setActiveTab] = useState<SourceTab>("apps");
  const [searchQuery, setSearchQuery] = useState("");

  // Merge initial sources with local overrides
  const sources = useMemo(() => {
    const merged = initialSources.map((source) => ({
      ...source,
      enabled: sourceOverrides[source.id] ?? source.enabled,
      autoStart: autoStartOverrides[source.id] ?? source.autoStart,
      useEntrypoint: entrypointOverrides[source.id] ?? source.useEntrypoint,
    }));
    
    // Add custom sources
    return [...merged, ...customSources];
  }, [initialSources, sourceOverrides, autoStartOverrides, entrypointOverrides, customSources]);

  // Toggle a source on/off
  const toggleSource = useCallback((id: string, enabled: boolean) => {
    // Check if it's a custom source
    const customIndex = customSources.findIndex((s) => s.id === id);
    if (customIndex !== -1) {
      setCustomSources((prev) =>
        prev.map((s) => (s.id === id ? { ...s, enabled } : s))
      );
    } else {
      setSourceOverrides((prev) => ({ ...prev, [id]: enabled }));
    }
  }, [customSources]);

  // Toggle auto-start for a source
  const toggleAutoStart = useCallback((id: string, autoStart: boolean) => {
    // Check if it's a custom source
    const customIndex = customSources.findIndex((s) => s.id === id);
    if (customIndex !== -1) {
      setCustomSources((prev) =>
        prev.map((s) => (s.id === id ? { ...s, autoStart } : s))
      );
    } else {
      setAutoStartOverrides((prev) => ({ ...prev, [id]: autoStart }));
    }
  }, [customSources]);

  // Toggle entrypoint usage for a source
  const toggleEntrypoint = useCallback((id: string, useEntrypoint: boolean) => {
    // Check if it's a custom source
    const customIndex = customSources.findIndex((s) => s.id === id);
    if (customIndex !== -1) {
      setCustomSources((prev) =>
        prev.map((s) => (s.id === id ? { ...s, useEntrypoint } : s))
      );
    } else {
      setEntrypointOverrides((prev) => ({ ...prev, [id]: useEntrypoint }));
    }
  }, [customSources]);

  // Update settings
  const updateSettings = useCallback((updates: Partial<ProcessComposeSettings>) => {
    setSettings((prev) => ({ ...prev, ...updates }));
  }, []);

  // Add a custom process
  const addCustomSource = useCallback(
    (source: Omit<ProcessSource, "id" | "type">) => {
      const id = `custom-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
      setCustomSources((prev) => [
        ...prev,
        { ...source, id, type: "custom", enabled: true },
      ]);
    },
    []
  );

  // Remove a custom process
  const removeCustomSource = useCallback((id: string) => {
    setCustomSources((prev) => prev.filter((s) => s.id !== id));
  }, []);

  // Update a custom process
  const updateCustomSource = useCallback(
    (id: string, updates: Partial<ProcessSource>) => {
      setCustomSources((prev) =>
        prev.map((s) => (s.id === id ? { ...s, ...updates } : s))
      );
    },
    []
  );

  // Get enabled sources only
  const getEnabledSources = useCallback(() => {
    return sources.filter((s) => s.enabled);
  }, [sources]);

  // Generate Nix expression
  const generateNix = useCallback(
    (format: NixOutputFormat = "partial"): GeneratedNixConfig => {
      const enabled = getEnabledSources();
      
      // Separate apps, scripts, tasks, and custom
      const appSources = enabled.filter((s) => s.type === "app");
      const _scriptSources = enabled.filter((s) => s.type === "script");
      const _taskSources = enabled.filter((s) => s.type === "task");
      const customProcesses = enabled.filter((s) => s.type === "custom");

      let content = "";
      
      if (format === "partial") {
        // Generate a partial that can be imported
        content = `# Process Compose Configuration
# Generated by StackPanel
# Path: .stackpanel/gen/process-compose.nix

{ lib, ... }:
{
  stackpanel.process-compose = {
    enable = ${settings.enable};
    commandName = "${settings.commandName}";

    formatWatcher = {
      enable = ${settings.formatWatcher.enable};
      extensions = [ ${settings.formatWatcher.extensions.map((e) => `"${e}"`).join(" ")} ];
${settings.formatWatcher.command ? `      command = "${settings.formatWatcher.command}";\n` : ""}    };

${Object.keys(settings.environment).length > 0 ? `    environment = {
${Object.entries(settings.environment)
  .map(([k, v]) => `      ${k} = "${v}";`)
  .join("\n")}
    };
` : ""}
${customProcesses.length > 0 ? `    processes = {
${customProcesses
  .map(
    (p) => `      ${p.name} = {
        command = "${p.command}";
${p.workingDir ? `        working_dir = "${p.workingDir}";\n` : ""}${p.namespace ? `        namespace = "${p.namespace}";\n` : ""}      };`
  )
  .join("\n")}
    };
` : ""}  };

${appSources.length > 0 ? `  # App process-compose settings
${appSources
  .map((a) => `  stackpanel.apps.${a.appName}.process-compose.enable = true;`)
  .join("\n")}
` : ""}
${initialSources.filter((s) => s.type === "app" && !sourceOverrides[s.id] && s.enabled === false).length > 0 ? `  # Disabled apps
${initialSources
  .filter((s) => s.type === "app" && sourceOverrides[s.id] === false)
  .map((a) => `  stackpanel.apps.${a.appName}.process-compose.enable = false;`)
  .join("\n")}
` : ""}}
`;
      } else if (format === "inline") {
        // Generate inline Nix suitable for pasting
        content = `{
  stackpanel.process-compose = {
    enable = ${settings.enable};
    commandName = "${settings.commandName}";
    formatWatcher.enable = ${settings.formatWatcher.enable};
${customProcesses.length > 0 ? `    processes = {
${customProcesses
  .map(
    (p) => `      ${p.name} = {
        command = "${p.command}";
${p.workingDir ? `        working_dir = "${p.workingDir}";\n` : ""}${p.namespace ? `        namespace = "${p.namespace}";\n` : ""}      };`
  )
  .join("\n")}
    };
` : ""}  };
}
`;
      } else {
        // Full format includes everything
        content = `# Full Process Compose Configuration
# Generated by StackPanel

{ config, lib, pkgs, ... }:
{
  stackpanel.process-compose = {
    enable = ${settings.enable};
    commandName = "${settings.commandName}";

    formatWatcher = {
      enable = ${settings.formatWatcher.enable};
      extensions = [ ${settings.formatWatcher.extensions.map((e) => `"${e}"`).join(" ")} ];
${settings.formatWatcher.command ? `      command = "${settings.formatWatcher.command}";\n` : ""}    };

    environment = {
${Object.entries(settings.environment)
  .map(([k, v]) => `      ${k} = "${v}";`)
  .join("\n")}
    };

    processes = {
${customProcesses
  .map(
    (p) => `      ${p.name} = {
        command = "${p.command}";
${p.workingDir ? `        working_dir = "${p.workingDir}";\n` : ""}${p.namespace ? `        namespace = "${p.namespace}";\n` : ""}      };`
  )
  .join("\n")}
    };
  };
}
`;
      }

      return {
        content,
        format,
        partialPath: format === "partial" ? ".stackpanel/gen/process-compose.nix" : undefined,
      };
    },
    [getEnabledSources, settings, initialSources, sourceOverrides]
  );

  // Generate YAML preview
  const generateYaml = useCallback(() => {
    const enabled = getEnabledSources();
    
    // Build processes object
    const processes: Record<string, ProcessConfig> = {};
    
    for (const source of enabled) {
      // Determine the command based on useEntrypoint setting
      let command = source.command;
      if (source.useEntrypoint && source.type === "app" && source.appName) {
        // Source entrypoint for env setup, then exec the actual command
        // Entrypoints ONLY inject environment variables - they don't run commands
        const entrypointPath = `packages/scripts/entrypoints/${source.appName}.sh`;
        command = `if [[ -f ${entrypointPath} ]]; then source ${entrypointPath} --dev && exec ${source.command}; else exec ${source.command}; fi`;
      }
      
      processes[source.name] = {
        command,
        ...(source.workingDir && { working_dir: source.workingDir }),
        ...(source.namespace && { namespace: source.namespace }),
        // If autoStart is false, process shows in TUI but doesn't start automatically
        ...(!source.autoStart && { disabled: true }),
      };
    }

    // Add format watcher if enabled
    if (settings.formatWatcher.enable) {
      const exts = settings.formatWatcher.extensions.join(",");
      const cmd = settings.formatWatcher.command ?? "turbo run format --continue";
      processes["format-watch"] = {
        command: `watchexec --exts ${exts} -- ${cmd}`,
        namespace: "infra",
      };
    }

    // Build environment list
    const environment = Object.entries(settings.environment).map(
      ([k, v]) => `${k}=${v}`
    );

    const config: ProcessComposeYamlConfig = {
      version: "0.5",
      processes,
      ...(environment.length > 0 && { environment }),
    };

    // Convert to YAML (simple implementation)
    return toYaml(config);
  }, [getEnabledSources, settings]);

  return {
    sources,
    customSources,
    settings,
    activeTab,
    searchQuery,
    setActiveTab,
    setSearchQuery,
    toggleSource,
    toggleAutoStart,
    toggleEntrypoint,
    updateSettings,
    addCustomSource,
    removeCustomSource,
    updateCustomSource,
    generateNix,
    generateYaml,
    getEnabledSources,
  };
}

// =============================================================================
// YAML Generator (simple implementation)
// =============================================================================

function toYaml(obj: unknown, indent = 0): string {
  const spaces = "  ".repeat(indent);
  
  if (obj === null || obj === undefined) {
    return "null";
  }
  
  if (typeof obj === "string") {
    // Quote strings that contain special characters
    if (obj.includes(":") || obj.includes("#") || obj.includes("\n") || obj.startsWith(" ")) {
      return `"${obj.replace(/"/g, '\\"')}"`;
    }
    return obj;
  }
  
  if (typeof obj === "number" || typeof obj === "boolean") {
    return String(obj);
  }
  
  if (Array.isArray(obj)) {
    if (obj.length === 0) return "[]";
    return obj.map((item) => `${spaces}- ${toYaml(item, indent)}`).join("\n");
  }
  
  if (typeof obj === "object") {
    const entries = Object.entries(obj);
    if (entries.length === 0) return "{}";
    
    return entries
      .map(([key, value]) => {
        if (typeof value === "object" && value !== null && !Array.isArray(value)) {
          return `${spaces}${key}:\n${toYaml(value, indent + 1)}`;
        }
        if (Array.isArray(value)) {
          return `${spaces}${key}:\n${toYaml(value, indent + 1)}`;
        }
        return `${spaces}${key}: ${toYaml(value, indent)}`;
      })
      .join("\n");
  }
  
  return String(obj);
}
