"use client";

import { useState, useCallback, useEffect, useMemo } from "react";
import {
  Pencil,
  Trash2,
  FolderOpen,
  Lock,
  VariableIcon,
  ChevronRight,
  ChevronDown,
  Loader2,
  Circle,
  Eye,
  EyeOff,
  Calculator,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { useResolvedApps, useNixConfig } from "@/lib/use-nix-config";
import type { App, AppTask } from "@/lib/types";
import { AppVariableType } from "@stackpanel/proto";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";
import { AgentHttpClient, type TurboPackage } from "@/lib/agent";
import { useAgentSSEEvent } from "@/lib/agent-sse-provider";
import { AddAppDialog } from "./apps/add-app-dialog";
import { AddVariableDialog } from "./variables/add-variable-dialog";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Link } from "@tanstack/react-router";

// Compute stable port from project name and service name
// Mirrors the Nix stablePort function from ports.nix
function computeStablePort(repo: string, service: string): number {
  const MIN_PORT = 3000;
  const MAX_PORT = 10000;
  const MODULUS = 100;

  // Simple hash function using string char codes
  const hashString = (s: string): number => {
    let hash = 0;
    for (let i = 0; i < s.length; i++) {
      const char = s.charCodeAt(i);
      hash = (hash << 5) - hash + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash);
  };

  // Compute project base port
  const range = MAX_PORT - MIN_PORT;
  const repoHash = hashString(repo);
  const offset = repoHash % range;
  const roundedOffset = offset - (offset % MODULUS);
  const projectBase = MIN_PORT + roundedOffset;

  // Compute service port within the project range
  const serviceHash = hashString(service);
  const serviceOffset = serviceHash % MODULUS;
  const servicePort = projectBase + serviceOffset;

  return servicePort;
}

interface TaskWithCommand {
  name: string;
  command: string;
  isOverridden: boolean;
}

interface DisplayVariable {
  id: string;
  name: string;
  type: AppVariableType | string;
  description: string;
  value?: string;
  isSecret: boolean;
}

export function AppsPanelAlt() {
  const { token } = useAgentContext();
  const { data: resolvedApps, isLoading, error, refetch } = useResolvedApps();
  const { data: nixConfig } = useNixConfig();

  // Get project name from config, fallback to "stackpanel"
  const projectName = nixConfig?.projectName ?? "stackpanel";

  // Turbo package graph state - source of truth for available tasks
  const [packageGraph, setPackageGraph] = useState<TurboPackage[]>([]);
  const [_isLoadingPackages, setIsLoadingPackages] = useState(false);

  const [expandedApp, setExpandedApp] = useState<string | null>(null);
  const [isDeleting, setIsDeleting] = useState<string | null>(null);
  const [editingTask, setEditingTask] = useState<{
    appId: string;
    taskName: string;
  } | null>(null);
  const [taskCommandOverride, setTaskCommandOverride] = useState("");
  const [showEnvValues, setShowEnvValues] = useState(false);

  // Fetch turbo package graph
  const fetchPackageGraph = useCallback(async () => {
    if (!token) return;

    setIsLoadingPackages(true);
    try {
      const client = new AgentHttpClient("localhost", 9876, token);
      const packages = await client.getPackageGraph({ excludeRoot: true });
      setPackageGraph(packages);
    } catch (err) {
      console.error("Failed to fetch package graph:", err);
    } finally {
      setIsLoadingPackages(false);
    }
  }, [token]);

  // Initial fetch
  useEffect(() => {
    fetchPackageGraph();
  }, [fetchPackageGraph]);

  // Subscribe to turbo.changed events for auto-refetch
  useAgentSSEEvent("turbo.changed", () => {
    fetchPackageGraph();
  });

  // Subscribe to config.changed events for auto-refetch
  useAgentSSEEvent("config.changed", () => {
    refetch();
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

  // Merge app tasks with turbo tasks
  // Priority: app tasks provide the command, turbo tasks provide defaults
  const getTasksForApp = useCallback(
    (app: {
      path: string;
      tasks: Record<string, AppTask>;
    }): TaskWithCommand[] => {
      const turboTasks = getTurboTasksForApp(app.path);

      // Start with tasks defined in the app
      const tasks: TaskWithCommand[] = Object.entries(app.tasks ?? {}).map(
        ([taskName, task]) => {
          const turboCommand = turboTasks.get(taskName);
          return {
            name: taskName,
            command: task.command ?? turboCommand ?? `npm run ${taskName}`,
            isOverridden: !!task.command && task.command !== turboCommand,
          };
        },
      );

      // Add any turbo tasks not already in the app tasks
      for (const [taskName, command] of turboTasks) {
        if (!tasks.some((t) => t.name === taskName)) {
          tasks.push({
            name: taskName,
            command,
            isOverridden: false,
          });
        }
      }

      return tasks;
    },
    [getTurboTasksForApp],
  );

  // Convert resolved apps to display format
  const apps = useMemo(() => {
    if (!resolvedApps) return [];

    return Object.entries(resolvedApps).map(([appId, app]) => {
      const tasks = getTasksForApp(app);

      // Compute stable port for this app
      const stablePort = computeStablePort(projectName, appId);

      // Helper to determine if a variable is a secret
      const isSecretVariable = (
        varName: string,
        varType: AppVariableType | string,
      ): boolean => {
        // Check if it's a VARIABLE type referencing a known secret pattern
        const secretPatterns = [
          "SECRET",
          "KEY",
          "PASSWORD",
          "TOKEN",
          "CREDENTIAL",
        ];
        const nameIsSecret = secretPatterns.some((p) =>
          varName.toUpperCase().includes(p),
        );
        // APP_VARIABLE_TYPE_VARIABLE that references a secret
        const isVarRef = varType === AppVariableType.VARIABLE;
        return nameIsSecret && isVarRef;
      };

      // Convert variables map to display format
      const appVariables: DisplayVariable[] = Object.entries(
        app.variables ?? {},
      ).map(([varKey, v]) => {
        const isSecret = isSecretVariable(varKey, v.type);
        return {
          id: varKey,
          name: v.key || varKey,
          type: v.type,
          description: v.description ?? "",
          value: v.value,
          isSecret,
        };
      });

      // Split by secret flag
      const secrets = appVariables.filter((v) => v.isSecret);
      const variables = appVariables.filter((v) => !v.isSecret);

      return {
        id: appId,
        name: app.name,
        path: app.path,
        domain: app.domain ?? "",
        type: app.type,
        port: app.port ?? stablePort,
        stablePort,
        description: app.description,
        tasks,
        secrets,
        variables,
        isRunning: false, // TODO: Query process-compose for running state
        _resolved: app,
      };
    });
  }, [resolvedApps, getTasksForApp, projectName]);

  // Auto-expand first app if none expanded
  useEffect(() => {
    if (apps.length > 0 && !expandedApp) {
      setExpandedApp(apps[0].id);
    }
  }, [apps, expandedApp]);

  const handleDelete = async (appId: string) => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    if (!confirm(`Are you sure you want to delete "${appId}"?`)) {
      return;
    }

    setIsDeleting(appId);
    try {
      const client = new NixClient({ token });
      const appsClient = client.mapEntity<App>("apps");

      await appsClient.remove(appId);
      toast.success(`Deleted app "${appId}"`);
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to delete app");
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
    toast.success(`Updated command for ${editingTask.taskName}`);
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
    <>
      <div className="max-w-5xl">
        {/* Page Header */}
        <div className="mb-6 flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-semibold mb-1">Apps</h2>
            <p className="text-sm text-muted-foreground">
              Manage your monorepo apps with linked tasks and variables
              {totalApps > 0 && (
                <span className="ml-2">
                  • {totalApps} {totalApps === 1 ? "app" : "apps"} •{" "}
                  {totalTasks} tasks • {totalVariables} variables
                </span>
              )}
            </p>
          </div>
          <AddAppDialog onSuccess={refetch} />
        </div>

        {/* Apps List */}
        {apps.length === 0 ? (
          <div className="border border-border rounded-lg bg-card p-12 text-center">
            <FolderOpen className="mx-auto mb-4 h-12 w-12 text-muted-foreground" />
            <p className="text-muted-foreground">
              No apps configured yet. Add your first app to get started.
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {apps.map((app) => {
              const isExpanded = expandedApp === app.id;
              const isBeingDeleted = isDeleting === app.id;

              return (
                <div
                  key={app.id}
                  className="border border-border rounded-lg bg-card overflow-hidden"
                >
                  {/* App Header */}
                  <div className="p-4 flex items-center justify-between">
                    <div className="flex items-center gap-3 flex-1">
                      <button
                        onClick={() =>
                          setExpandedApp(isExpanded ? null : app.id)
                        }
                        className="text-muted-foreground hover:text-foreground"
                      >
                        {isExpanded ? (
                          <ChevronDown className="h-4 w-4" />
                        ) : (
                          <ChevronRight className="h-4 w-4" />
                        )}
                      </button>
                      <div className="flex items-center gap-2">
                        {/* Running indicator */}
                        <Circle
                          className={`h-2 w-2 ${
                            app.isRunning
                              ? "fill-green-500 text-green-500"
                              : "fill-muted text-muted"
                          }`}
                        />
                        <h3 className="font-medium">{app.name}</h3>
                        {app.type && (
                          <Badge variant="secondary" className="text-xs">
                            {app.type}
                          </Badge>
                        )}
                        <Tooltip>
                          <TooltipTrigger>
                            <span className="text-xs text-muted-foreground font-mono">
                              :{app.port}
                            </span>
                          </TooltipTrigger>
                          <TooltipContent>
                            This is your app's computed{" "}
                            <Link
                              href={`http://localhost:4000/reference/ports`}
                            >
                              stable port
                            </Link>
                            .
                          </TooltipContent>
                        </Tooltip>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                        disabled={!token}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-destructive"
                        onClick={() => handleDelete(app.id)}
                        disabled={!token || isBeingDeleted}
                      >
                        {isBeingDeleted ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <Trash2 className="h-4 w-4" />
                        )}
                      </Button>
                    </div>
                  </div>

                  {/* Expanded Content */}
                  {isExpanded && (
                    <div className="border-t border-border px-4 py-3 space-y-4 bg-muted/20">
                      {/* App Details */}
                      <div className="text-sm grid grid-cols-2 gap-2">
                        <div className="flex items-center gap-2 text-muted-foreground text-xl">
                          <FolderOpen className="h-3 w-3" />
                          <span className="text-xs font-mono font-medium">
                            {app.path}
                          </span>
                        </div>
                        {app.domain && (
                          <div className="text-xs text-muted-foreground">
                            Domain:{" "}
                            <span className="text-foreground font-mono font-medium">
                              {app.domain}
                            </span>
                          </div>
                        )}
                        <div className="flex items-center gap-2 text-muted-foreground font-medium text-xl">
                          {app.stablePort && (
                            <span className="text-xs font-mono">
                              {app.stablePort}
                            </span>
                          )}
                        </div>

                        {app.description && (
                          <div className="text-xs text-muted-foreground col-span-2">
                            {app.description}
                          </div>
                        )}
                      </div>

                      {/* Tasks Section */}
                      <div>
                        <div className="flex items-center justify-between mb-2">
                          <div className="text-xs font-medium text-muted-foreground">
                            Tasks ({app.tasks.length})
                          </div>
                        </div>
                        {app.tasks.length === 0 ? (
                          <p className="text-xs text-muted-foreground">
                            No tasks discovered. Make sure the app has a
                            package.json with scripts.
                          </p>
                        ) : (
                          <div className="space-y-1.5">
                            {app.tasks.map((task) => {
                              const isEditing =
                                editingTask?.appId === app.id &&
                                editingTask?.taskName === task.name;

                              return (
                                <div
                                  key={task.name}
                                  className="group flex items-center gap-2 px-3 py-2 rounded-md border border-border bg-background/70 hover:bg-background/10 cursor-pointer"
                                >
                                  {/*<Play className="h-3 w-3 text-emerald-300 shrink-0" />*/}
                                  <span className="text-xs font-medium min-w-32 text-primary/80 font-mono text-right pr-2">
                                    {task.name}
                                  </span>
                                  {isEditing ? (
                                    <div className="flex-1 flex items-center gap-2">
                                      <Input
                                        value={taskCommandOverride}
                                        onChange={(e) =>
                                          setTaskCommandOverride(e.target.value)
                                        }
                                        className="h-7 text-xs font-mono flex-1 font-medium"
                                        autoFocus
                                      />
                                      <Button
                                        size="sm"
                                        className="h-7 text-xs"
                                        onClick={handleTaskSave}
                                      >
                                        Save
                                      </Button>
                                      <Button
                                        size="sm"
                                        variant="ghost"
                                        className="h-7 text-xs"
                                        onClick={handleTaskCancel}
                                      >
                                        Cancel
                                      </Button>
                                    </div>
                                  ) : (
                                    <>
                                      <span className="text-xs text-muted-foreground font-mono truncate flex-1 border-l pl-4">
                                        {task.command}
                                      </span>
                                      <Button
                                        variant="ghost"
                                        size="icon"
                                        className="h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity"
                                        onClick={() =>
                                          handleTaskEdit(
                                            app.id,
                                            task.name,
                                            task.command,
                                          )
                                        }
                                      >
                                        <Pencil className="h-3 w-3" />
                                      </Button>
                                    </>
                                  )}
                                </div>
                              );
                            })}
                          </div>
                        )}
                      </div>

                      {/* Environment Variables Section (merged variables + secrets) */}
                      <div>
                        <div className="flex items-center justify-between mb-2">
                          <div className="text-xs font-medium text-muted-foreground">
                            <VariableIcon className="h-3 w-3 inline mr-1" />
                            Environment Variables (
                            {app.variables.length + app.secrets.length})
                          </div>
                          <button
                            onClick={() => setShowEnvValues(!showEnvValues)}
                            className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
                          >
                            {showEnvValues ? (
                              <>
                                <EyeOff className="h-3 w-3" />
                                <span>Hide values</span>
                              </>
                            ) : (
                              <>
                                <Eye className="h-3 w-3" />
                                <span>Show values</span>
                              </>
                            )}
                          </button>
                        </div>
                        {app.variables.length + app.secrets.length === 0 ? (
                          <p className="text-xs text-muted-foreground">
                            No environment variables configured.
                          </p>
                        ) : (
                          <div className="flex flex-wrap gap-2">
                            {/* Render all variables */}
                            {app.variables.map((variable) => {
                              const isComputed =
                                variable.type === AppVariableType.VALS;
                              return (
                                <div
                                  key={variable.id}
                                  className="group flex items-center gap-2 px-3 py-1.5 rounded-md border border-border bg-background text-xs hover:border-blue-500/50 transition-colors cursor-pointer"
                                >
                                  {isComputed ? (
                                    <Calculator className="h-3 w-3 text-purple-500" />
                                  ) : (
                                    <VariableIcon className="h-3 w-3 text-blue-500" />
                                  )}
                                  <span className="font-medium font-mono">
                                    {variable.name}
                                  </span>
                                  {variable.value && (
                                    <>
                                      <span className="text-muted-foreground">
                                        =
                                      </span>
                                      <span className="text-muted-foreground font-mono truncate max-w-32">
                                        {showEnvValues
                                          ? variable.value
                                          : "••••••"}
                                      </span>
                                    </>
                                  )}
                                  <Pencil className="h-3 w-3 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                                </div>
                              );
                            })}
                            {/* Render all secrets */}
                            {app.secrets.map((secret) => (
                              <div
                                key={secret.id}
                                className="group flex items-center gap-2 px-3 py-1.5 rounded-md border border-orange-500/30 bg-orange-500/5 text-xs hover:border-orange-500/50 transition-colors cursor-pointer"
                              >
                                <Lock className="h-3 w-3 text-orange-500" />
                                <span className="font-medium font-mono">
                                  {secret.name}
                                </span>
                                {secret.value && (
                                  <>
                                    <span className="text-muted-foreground">
                                      =
                                    </span>
                                    <span className="text-muted-foreground font-mono truncate max-w-32">
                                      {showEnvValues ? secret.value : "••••••"}
                                    </span>
                                  </>
                                )}
                                {!secret.value && (
                                  <span className="text-muted-foreground">
                                    ••••••
                                  </span>
                                )}
                                <Pencil className="h-3 w-3 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                              </div>
                            ))}
                            {/* Add Variable chip */}
                            <AddVariableDialog onSuccess={refetch} />
                          </div>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}

export default AppsPanelAlt;
