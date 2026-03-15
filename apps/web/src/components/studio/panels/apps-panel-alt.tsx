"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@ui/tooltip";
import {
  ChevronDown,
  ChevronRight,
  Circle,
  FolderOpen,
  Loader2,
  Trash2,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  type ProcessComposeStatusResponse,
  type TurboPackage,
} from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useAgentSSEEvent } from "@/lib/agent-sse-provider";
import type { App } from "@/lib/types";
import {
  useAppVariableLinks,
  useApps,
  useNixConfig,
  useVariables,
} from "@/lib/use-agent";
import { AddAppDialog } from "./apps/add-app-dialog";
import {
  AppExpandedContent,
  type AppFramework,
} from "./apps/app-expanded-content";
import type { AppModulePanel } from "./shared/panel-types";
import { useAppMutations } from "./apps/hooks";
import type { DisplayVariable, TaskWithCommand } from "./apps/types";
import type { AvailableVariable } from "./apps/app-variables-section/types";
import {
  computeStablePort,
  flattenEnvironmentVariables,
  getEnvironmentNames,
} from "./apps/utils";
import {
  buildVariableLinkReference,
  getVariableType,
  parseVariableLinkReference,
} from "./variables/constants";
import { PanelHeader } from "./shared/panel-header";
import { Card, CardHeader } from "@/components/ui/card";

export function AppsPanelAlt() {
  const { token } = useAgentContext();
  const agentClient = useAgentClient();
  const { data: rawApps, isLoading, error, refetch } = useApps();
  const { data: nixConfig } = useNixConfig();
  const { data: rawVariables } = useVariables();
  const { data: appVariableLinks, refetch: refetchAppVariableLinks } =
    useAppVariableLinks();

  // Get project name from config, fallback to "stackpanel"
  const projectName =
    (typeof nixConfig?.projectName === "string"
      ? nixConfig.projectName
      : null) ?? "stackpanel";

  // Extract PANEL_TYPE_APP_CONFIG panels from panelsComputed
  // Panels come from nix eval: config.panelsComputed (flake path) or config.ui.panels (CLI path)
  const appConfigPanels = useMemo((): AppModulePanel[] => {
    const cfg = nixConfig as Record<string, unknown> | null | undefined;
    if (!cfg) return [];

    // Try flake eval path first (panelsComputed), then CLI config path (ui.panels)
    const panels =
      cfg.panelsComputed ??
      (cfg.ui as Record<string, unknown> | undefined)?.panels;
    if (!panels || typeof panels !== "object") return [];

    type RawPanel = AppModulePanel & { type?: string };
    return Object.values(panels as Record<string, RawPanel>).filter(
      (p): p is RawPanel => p.type === "PANEL_TYPE_APP_CONFIG",
    );
  }, [nixConfig]);

  // Separate panels by category:
  // - Container panels go to the Docker tab
  // - Deployment panels (fly, cloudflare) go to the Deployment tab
  // - Other panels go to the Modules tab
  const containerPanels = useMemo(() => {
    return appConfigPanels.filter((p) => p.module === "containers");
  }, [appConfigPanels]);

  const deploymentPanels = useMemo(() => {
    return appConfigPanels.filter(
      (p) => p.module === "deployment-fly" || p.module === "deployment-cloudflare",
    );
  }, [appConfigPanels]);

  const modulePanels = useMemo(() => {
    return appConfigPanels.filter(
      (p) =>
        p.module !== "containers" &&
        p.module !== "deployment-fly" &&
        p.module !== "deployment-cloudflare",
    );
  }, [appConfigPanels]);

  // Transform apps data to include id, stablePort, and isRunning fields
  const resolvedApps = useMemo(() => {
    if (!rawApps) return null;
    const result: Record<
      string,
      App & { id: string; stablePort: number; isRunning: boolean }
    > = {};
    for (const [id, app] of Object.entries(rawApps)) {
      result[id] = {
        ...app,
        id,
        stablePort: app.port ?? 3000,
        isRunning: false, // Will be updated from process-compose status
      };
    }
    return result;
  }, [rawApps]);

  // Turbo package graph state - source of truth for available tasks
  const [packageGraph, setPackageGraph] = useState<TurboPackage[]>([]);
  const [_isLoadingPackages, setIsLoadingPackages] = useState(false);

  // Process-compose state - for tracking running processes
  const [processComposeStatus, setProcessComposeStatus] =
    useState<ProcessComposeStatusResponse | null>(null);

  const [expandedApp, setExpandedApp] = useState<string | null>(null);
  const [isDeleting, setIsDeleting] = useState<string | null>(null);
  const [editingTask, setEditingTask] = useState<{
    appId: string;
    taskName: string;
  } | null>(null);
  const [taskCommandOverride, setTaskCommandOverride] = useState("");

  // Use the extracted mutations hook
  const {
    handleAddVariableToApp,
    handleUpdateVariableInApp,
    handleUpdateEnvironmentsForApp,
    handleDeleteVariableFromApp,
    handleUpdateFramework,
    handleDeleteApp,
  } = useAppMutations({
    token,
    resolvedApps: resolvedApps ?? undefined,
    refetch,
  });

  const environmentOptions = useMemo(() => {
    const defaults = ["dev", "staging", "prod"];
    const appDefined = Object.values(resolvedApps ?? {}).flatMap((app) =>
      getEnvironmentNames(app.environments),
    );
    return Array.from(new Set([...defaults, ...appDefined]));
  }, [resolvedApps]);

  // Transform raw variables into AvailableVariable format for the dropdown
  const availableVariables: AvailableVariable[] = useMemo(() => {
    if (!rawVariables) return [];
    return Object.entries(rawVariables).map(([id, variable]) => {
      // Variable is now an object with { value: string }
      const value =
        typeof variable === "string" ? variable : (variable?.value ?? "");
      // Use the full ID as the display name (e.g., "/dev/DATABASE_URL")
      // This avoids confusion when multiple vars have the same last segment (e.g., "port")
      const name = id;
      // Determine type from ID prefix (keygroup)
      const typeName = getVariableType(id, value);
      return { id, name, typeName };
    });
  }, [rawVariables]);

  // Fetch turbo package graph
  const fetchPackageGraph = useCallback(async () => {
    if (!token) return;

    setIsLoadingPackages(true);
    try {
      const client = agentClient;
      const packages = await client.getPackageGraph({ excludeRoot: true });
      setPackageGraph(packages);
    } catch (err) {
      console.error("Failed to fetch package graph:", err);
    } finally {
      setIsLoadingPackages(false);
    }
  }, [token, agentClient]);

  // Fetch process-compose status
  const fetchProcessComposeStatus = useCallback(async () => {
    if (!token) return;

    try {
      const client = agentClient;
      const status = await client.getProcessComposeProcesses();
      setProcessComposeStatus(status);
    } catch (err) {
      console.error("Failed to fetch process-compose status:", err);
    }
  }, [token, agentClient]);

  // Initial fetch
  useEffect(() => {
    fetchPackageGraph();
    fetchProcessComposeStatus();
  }, [fetchPackageGraph, fetchProcessComposeStatus]);

  // Poll process-compose status every 5 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      fetchProcessComposeStatus();
    }, 5000);
    return () => clearInterval(interval);
  }, [fetchProcessComposeStatus]);

  // Subscribe to turbo.changed events for auto-refetch
  useAgentSSEEvent("turbo.changed", () => {
    fetchPackageGraph();
  });

  // Subscribe to config.changed events for auto-refetch
  useAgentSSEEvent("config.changed", () => {
    refetch();
    refetchAppVariableLinks();
  });

  // Get turbo tasks for a specific app path from the package graph
  const getTurboTasksForApp = useCallback(
    (appPath: string): Map<string, string> => {
      const pkg = packageGraph.find((p) => p.path === appPath);
      if (!pkg) return new Map();

      const taskMap = new Map<string, string>();
      for (const t of pkg.tasks) {
        taskMap.set(t.name, `turbo run ${t.name} --filter=${pkg.name}`);
      }
      return taskMap;
    },
    [packageGraph],
  );

  // Get all tasks for an app from turbo (simplified - tasks come from turbo, not app config)
  const getTasksForApp = useCallback(
    (app: App): TaskWithCommand[] => {
      const turboTasks = getTurboTasksForApp(app.path);

      // Tasks come from turbo package graph only
      const tasks: TaskWithCommand[] = Array.from(turboTasks.entries()).map(
        ([name, command]) => ({
          name,
          command,
          isOverridden: false,
        }),
      );

      return tasks;
    },
    [getTurboTasksForApp],
  );

  // Create a set of running process names from process-compose
  const runningProcesses = useMemo(() => {
    if (!processComposeStatus?.running || !processComposeStatus.processes) {
      return new Set<string>();
    }
    return new Set(
      processComposeStatus.processes
        .filter((p) => p.is_running)
        .map((p) => p.name),
    );
  }, [processComposeStatus]);

  // Convert resolved apps to display format
  const apps = useMemo(() => {
    if (!resolvedApps) return [];

    return Object.entries(resolvedApps).map(([appId, app]) => {
      const tasks = getTasksForApp(app);

      // Compute stable port for this app
      const stablePort = computeStablePort(projectName, appId);

      // Convert environments to display format - flatten variables from all environments
      // With simplified schema: env is map<string, string> (key -> value)
      const flattenedVars = flattenEnvironmentVariables(app.environments);
      const appVariables: DisplayVariable[] = flattenedVars.map((mapping) => {
        const linkedVariableId =
          mapping.environments
            .map((envName) => appVariableLinks?.[appId]?.[envName]?.[mapping.envKey])
            .find(Boolean) ??
          parseVariableLinkReference(mapping.value);
        const linkedVariable = linkedVariableId
          ? rawVariables?.[linkedVariableId]
          : undefined;
        const linkedValue =
          typeof linkedVariable === "string"
            ? linkedVariable
            : (linkedVariable?.value ?? "");
        const typeName = linkedVariableId
          ? getVariableType(linkedVariableId, linkedValue)
          : "config";
        const isSecret = typeName === "secret";
        return {
          envKey: mapping.envKey,
          value: linkedVariableId
            ? buildVariableLinkReference(linkedVariableId)
            : mapping.value,
          environments: mapping.environments,
          isSecret,
          typeName,
        };
      });

      // Split by secret flag
      const secrets = appVariables.filter((v) => v.isSecret);
      const variables = appVariables.filter((v) => !v.isSecret);

      // Check if this app is running in process-compose
      // Process names match app IDs (e.g., "web", "server")
      const isRunning = runningProcesses.has(appId);

      return {
        id: appId,
        name: app.name,
        path: app.path,
        domain: app.domain ?? "",
        type: app.type,
        port: app.port ?? stablePort,
        stablePort,
        description: app.description,
        environments: getEnvironmentNames(app.environments),
        tasks,
        secrets,
        variables,
        isRunning,
        _resolved: app,
      };
    });
  }, [appVariableLinks, resolvedApps, getTasksForApp, projectName, rawVariables, runningProcesses]);

  // Derive the active framework from the app's type field
  const getFrameworkForApp = (appType?: string): AppFramework => {
    if (appType === "go" || appType === "bun") return appType;
    return null;
  };

  // Auto-expand first app if none expanded
  useEffect(() => {
    if (apps.length > 0 && !expandedApp) {
      setExpandedApp(apps[0].id);
    }
  }, [apps, expandedApp]);

  const handleDelete = async (appId: string) => {
    setIsDeleting(appId);
    try {
      await handleDeleteApp(appId);
    } finally {
      setIsDeleting(null);
    }
  };

  const handleTaskEdit = (appId: string, taskName: string, command: string) => {
    setEditingTask({ appId, taskName });
    setTaskCommandOverride(command);
  };

  const handleTaskSave = async () => {
    if (!editingTask) return;
    // TODO: Save task command override to config
    setEditingTask(null);
    setTaskCommandOverride("");
  };

  const handleTaskCancel = () => {
    setEditingTask(null);
    setTaskCommandOverride("");
  };

  const totalApps = apps.length;
  const totalTasks = apps.reduce((acc, app) => acc + app.tasks.length, 0);
  const totalVariables = apps.reduce(
    (acc, app) => acc + app.variables.length + app.secrets.length,
    0,
  );

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-4">
        <p className="text-destructive text-sm">
          Error loading apps: {error.message}
        </p>
      </div>
    );
  }

  return (
    <TooltipProvider>
      <div className="space-y-4">
        <PanelHeader
          title="Apps"
          description={`${totalApps} apps • ${totalTasks} tasks • ${totalVariables} variables`}
          guideKey="apps"
          actions={<AddAppDialog onSuccess={refetch} />}
        />

        {/* Apps List */}
        {apps.length === 0 ? (
          <div className="rounded-lg border border-dashed border-border bg-muted/30 p-8 text-center">
            <FolderOpen className="mx-auto h-10 w-10 text-muted-foreground/50" />
            <p className="mt-3 text-sm text-muted-foreground">
              No apps configured yet.
            </p>
            <p className="text-xs text-muted-foreground/70">
              Add your first app to get started.
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {apps.map((app) => {
              const isExpanded = expandedApp === app.id;
              const isBeingDeleted = isDeleting === app.id;

              return (
                <Card key={app.id} className="animate-in zoom-in">
                  {/* App Header */}
                  <CardHeader
                    className="flex items-center gap-3 -my-4 py-2  cursor-pointer hover:bg-muted/30 transition-colors"
                    onClick={() => setExpandedApp(isExpanded ? null : app.id)}
                  >
                    <button
                      className="shrink-0 text-muted-foreground"
                      aria-label={isExpanded ? "Collapse" : "Expand"}
                    >
                      {isExpanded ? (
                        <ChevronDown className="h-4 w-4" />
                      ) : (
                        <ChevronRight className="h-4 w-4" />
                      )}
                    </button>

                    <div className="flex items-center gap-2 min-w-0 flex-1">
                      <Circle
                        className={`h-2 w-2 shrink-0 ${
                          app.isRunning
                            ? "fill-emerald-500 text-emerald-500"
                            : "fill-muted text-muted"
                        }`}
                      />
                      <span className="font-medium text-sm truncate">
                        {app.name}
                      </span>
                      {app.type && (
                        <Badge variant="outline" className="text-xs shrink-0">
                          {app.type}
                        </Badge>
                      )}
                    </div>

                    <div className="flex items-center gap-4 text-xs text-muted-foreground shrink-0">
                      <div className="flex items-center gap-1">
                        <span className="font-mono">{app.tasks.length}</span>
                        <span>tasks</span>
                      </div>
                      <div className="flex items-center gap-1">
                        <span className="font-mono">
                          {app.variables.length + app.secrets.length}
                        </span>
                        <span>vars</span>
                      </div>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <span className="text-xs text-muted-foreground font-mono">
                            :{app.port}
                          </span>
                        </TooltipTrigger>
                        <TooltipContent>
                          Stable port for this app
                        </TooltipContent>
                      </Tooltip>
                    </div>

                    <div className="flex items-center gap-1 shrink-0">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDelete(app.id);
                        }}
                        disabled={!token || isBeingDeleted}
                      >
                        {isBeingDeleted ? (
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        ) : (
                          <Trash2 className="h-3.5 w-3.5 text-muted-foreground hover:text-destructive" />
                        )}
                      </Button>
                    </div>
                  </CardHeader>

                  {/* Expanded Content with subnav */}
                  {isExpanded && (
                    <AppExpandedContent
                      app={app}
                      framework={getFrameworkForApp(app.type)}
                      environmentOptions={environmentOptions}
                      availableVariables={availableVariables}
                      disabled={!token}
                      modulePanels={modulePanels.filter(
                        (p) => p.apps[app.id] != null,
                      )}
                      containerPanels={containerPanels.filter(
                        (p) => p.apps[app.id] != null,
                      )}
                      deploymentPanels={deploymentPanels.filter(
                        (p) => p.apps[app.id] != null,
                      )}
                      editingTask={editingTask}
                      taskCommandOverride={taskCommandOverride}
                      onTaskEdit={handleTaskEdit}
                      onTaskSave={handleTaskSave}
                      onTaskCancel={handleTaskCancel}
                      onTaskCommandChange={setTaskCommandOverride}
                      onAddVariable={(envKey, value, environments) =>
                        handleAddVariableToApp(
                          app.id,
                          envKey,
                          value,
                          environments,
                        )
                      }
                      onUpdateVariable={(
                        oldEnvKey,
                        newEnvKey,
                        value,
                        environments,
                      ) =>
                        handleUpdateVariableInApp(
                          app.id,
                          oldEnvKey,
                          newEnvKey,
                          value,
                          environments,
                        )
                      }
                      onDeleteVariable={(envKey) =>
                        handleDeleteVariableFromApp(app.id, envKey)
                      }
                      onUpdateEnvironments={(environments) =>
                        handleUpdateEnvironmentsForApp(app.id, environments)
                      }
                      onFrameworkChange={(fw) =>
                        handleUpdateFramework(app.id, fw)
                      }
                    />
                  )}
                </Card>
              );
            })}
          </div>
        )}
      </div>
    </TooltipProvider>
  );
}

export default AppsPanelAlt;
