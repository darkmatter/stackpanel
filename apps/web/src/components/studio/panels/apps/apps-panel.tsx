"use client";

import { useState, useMemo, useCallback, useEffect } from "react";
import {
  ExternalLink,
  FolderOpen,
  Loader2,
  Pencil,
  Save,
  Search,
  Trash2,
  X,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { useResolvedApps, useVariables } from "@/lib/use-nix-config";
import type { ResolvedApp, App, AppTask, AppVariable } from "@/lib/types";
import { AppVariableType } from "@stackpanel/proto";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";
import { AgentHttpClient, type TurboPackage } from "@/lib/agent";
import { useAgentSSEEvent } from "@/lib/agent-sse-provider";

import { getTypeColor, getTypeLabel } from "./constants";
import { AppTasks } from "./app-tasks";
import { AppVariables } from "./app-variables";
import {
  AppFormFields,
  type AppFormValues,
  type AppForm,
  parsePortValue,
} from "./app-form-fields";
import { AddAppDialog } from "./add-app-dialog";

export function AppsPanel() {
  const { token } = useAgentContext();
  const { data: resolvedApps, isLoading, error, refetch } = useResolvedApps();
  const { data: allVariables } = useVariables();

  // Turbo package graph state - source of truth for available tasks
  const [packageGraph, setPackageGraph] = useState<TurboPackage[]>([]);
  const [_isLoadingPackages, setIsLoadingPackages] = useState(false);

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedType, setSelectedType] = useState<string | null>(null);
  const [editingApp, setEditingApp] = useState<string | null>(null);
  const [editFormRef, setEditFormRef] = useState<AppForm | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

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

  // Get all unique tasks from the package graph
  const allTasks = useMemo(() => {
    const taskSet = new Set<string>();
    for (const pkg of packageGraph) {
      for (const task of pkg.tasks) {
        taskSet.add(task.name);
      }
    }
    return Array.from(taskSet).sort();
  }, [packageGraph]);

  // Convert tasks to selectable items
  const taskItems = useMemo(() => {
    return allTasks.map((name) => ({
      id: name,
      name,
    }));
  }, [allTasks]);

  const variableItems = useMemo(() => {
    if (!allVariables) return [];
    return Object.entries(allVariables).map(([id, v]) => ({
      id,
      name: v.key || id,
      type: String(v.type),
    }));
  }, [allVariables]);

  // Filter apps based on search and type
  const filteredApps = useMemo(() => {
    if (!resolvedApps) return [];

    return Object.entries(resolvedApps).filter(([appId, app]) => {
      const matchesSearch =
        !searchQuery ||
        appId.toLowerCase().includes(searchQuery.toLowerCase()) ||
        app.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        app.description?.toLowerCase().includes(searchQuery.toLowerCase());

      const matchesType = !selectedType || app.type === selectedType;

      return matchesSearch && matchesType;
    });
  }, [resolvedApps, searchQuery, selectedType]);

  // Get unique types for filtering
  const availableTypes = useMemo(() => {
    if (!resolvedApps) return [];
    const types = new Set<string>();
    for (const app of Object.values(resolvedApps)) {
      if (app.type) types.add(app.type);
    }
    return Array.from(types);
  }, [resolvedApps]);

  const handleFormReady = useCallback((form: AppForm) => {
    setEditFormRef(form);
  }, []);

  const handleEdit = (appId: string, _app: ResolvedApp) => {
    setEditingApp(appId);
    // The form will be populated via defaultValues when AppFormFields mounts
  };

  const getEditDefaultValues = (app: ResolvedApp): Partial<AppFormValues> => ({
    id: "",
    name: app.name,
    description: app.description ?? "",
    path: app.path,
    type: app.type ?? "other",
    port: app.port?.toString() ?? "",
    domain: app.domain ?? "",
    tasks: Object.keys(app.tasks ?? {}),
    variables: Object.keys(app.variables ?? {}),
  });

  const handleSave = async (appId: string) => {
    if (!token || !editFormRef) {
      toast.error("Not connected to agent");
      return;
    }

    // Trigger validation
    const isValid = await editFormRef.trigger();
    if (!isValid) return;

    const values = editFormRef.getValues();

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const appsClient = client.mapEntity<App>("apps");

      // Convert tasks array to map format
      const tasksMap: Record<string, AppTask> = {};
      for (const taskName of values.tasks) {
        tasksMap[taskName] = {
          key: taskName,
          command: `bun run ${taskName}`,
          env: {},
        };
      }

      // Convert variables array to map format
      const variablesMap: Record<string, AppVariable> = {};
      for (const varName of values.variables) {
        variablesMap[varName] = {
          key: varName,
          type: AppVariableType.VARIABLE,
          value: varName,
        };
      }

      const updatedApp: App = {
        name: values.name || appId,
        description: values.description || undefined,
        path: values.path,
        type: values.type || undefined,
        port: parsePortValue(values.port),
        domain: values.domain || undefined,
        tasks: tasksMap,
        variables: variablesMap,
      };

      await appsClient.set(appId, updatedApp);
      toast.success(`Updated app "${appId}"`);
      setEditingApp(null);
      setEditFormRef(null);
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save app");
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancel = () => {
    setEditingApp(null);
    setEditFormRef(null);
  };

  const handleDelete = async (appId: string) => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    if (!confirm(`Are you sure you want to delete "${appId}"?`)) {
      return;
    }

    setIsDeleting(true);
    try {
      const client = new NixClient({ token });
      const appsClient = client.mapEntity<App>("apps");

      await appsClient.remove(appId);
      toast.success(`Deleted app "${appId}"`);
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to delete app");
    } finally {
      setIsDeleting(false);
    }
  };

  const totalApps = resolvedApps ? Object.keys(resolvedApps).length : 0;

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
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h2 className="font-semibold text-foreground text-xl">Apps</h2>
            <p className="text-muted-foreground text-sm">
              Manage your monorepo apps with linked tasks and variables
            </p>
          </div>

          <AddAppDialog onSuccess={refetch} />
        </div>

        {/* Filters */}
        <div className="flex flex-wrap items-center gap-4">
          <div className="relative flex-1">
            <Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
            <Input
              className="pl-9"
              placeholder="Search apps..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          <Select
            value={selectedType ?? "all"}
            onValueChange={(value) =>
              setSelectedType(value === "all" ? null : value)
            }
          >
            <SelectTrigger className="w-40">
              <SelectValue placeholder="All types" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All types</SelectItem>
              {availableTypes.map((type) => (
                <SelectItem key={type} value={type}>
                  {getTypeLabel(type)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          <div className="text-muted-foreground text-sm">
            {filteredApps.length} of {totalApps} app{totalApps !== 1 ? "s" : ""}
          </div>
        </div>

        {/* Apps List */}
        {filteredApps.length === 0 ? (
          <Card>
            <CardContent className="py-12 text-center">
              <FolderOpen className="mx-auto mb-4 h-12 w-12 text-muted-foreground" />
              <p className="text-muted-foreground">
                {totalApps === 0
                  ? "No apps configured yet. Add your first app to get started."
                  : "No apps match your search criteria."}
              </p>
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-4">
            {filteredApps.map(([appId, app]) => {
              const isEditing = editingApp === appId;

              return (
                <Card key={appId}>
                  <CardHeader className="pb-3">
                    <div className="flex items-start justify-between">
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <CardTitle className="text-base">
                            {app.name}
                          </CardTitle>
                          <Badge
                            variant="outline"
                            className={getTypeColor(app.type ?? "other")}
                          >
                            {getTypeLabel(app.type ?? "other")}
                          </Badge>
                        </div>
                        {app.description && (
                          <CardDescription>{app.description}</CardDescription>
                        )}
                      </div>
                      {!isEditing && (
                        <div className="flex items-center gap-1">
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8"
                                onClick={() => handleEdit(appId, app)}
                                disabled={!token}
                              >
                                <Pencil className="h-4 w-4" />
                              </Button>
                            </TooltipTrigger>
                            <TooltipContent>Edit app</TooltipContent>
                          </Tooltip>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8"
                                onClick={() => handleDelete(appId)}
                                disabled={!token || isDeleting}
                              >
                                <Trash2 className="h-4 w-4 text-destructive" />
                              </Button>
                            </TooltipTrigger>
                            <TooltipContent>Delete app</TooltipContent>
                          </Tooltip>
                        </div>
                      )}
                    </div>
                  </CardHeader>
                  <CardContent>
                    {isEditing ? (
                      <div className="space-y-4">
                        <AppFormFields
                          taskItems={taskItems}
                          variableItems={variableItems}
                          defaultValues={getEditDefaultValues(app)}
                          onFormReady={handleFormReady}
                        />

                        <div className="flex items-center gap-2 pt-2">
                          <Button
                            onClick={() => handleSave(appId)}
                            disabled={isSaving}
                            className="gap-2"
                          >
                            {isSaving ? (
                              <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                              <Save className="h-4 w-4" />
                            )}
                            Save
                          </Button>
                          <Button variant="outline" onClick={handleCancel}>
                            <X className="mr-2 h-4 w-4" />
                            Cancel
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <div className="space-y-4">
                        {/* App details */}
                        <div className="grid gap-2 text-sm">
                          <div className="flex items-center gap-2">
                            <FolderOpen className="h-4 w-4 text-muted-foreground" />
                            <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                              {app.path}
                            </code>
                          </div>
                          {app.port && (
                            <div className="flex items-center gap-2">
                              <span className="text-muted-foreground">
                                Port:
                              </span>
                              <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                                {app.port}
                              </code>
                            </div>
                          )}
                          {app.domain && (
                            <div className="flex items-center gap-2">
                              <span className="text-muted-foreground">
                                Domain:
                              </span>
                              <a
                                href={`http://${app.domain}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="flex items-center gap-1 text-accent hover:underline"
                              >
                                {app.domain}
                                <ExternalLink className="h-3 w-3" />
                              </a>
                            </div>
                          )}
                        </div>

                        {/* Linked tasks and variables */}
                        <div className="flex flex-wrap gap-4 border-t border-border pt-4">
                          <AppTasks tasks={app.tasks} />
                          <AppVariables variables={app.variables} />
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </div>
    </TooltipProvider>
  );
}
