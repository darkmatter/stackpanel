"use client";

import { useState, useMemo } from "react";
import {
  ChevronDown,
  ChevronRight,
  ExternalLink,
  FolderOpen,
  Loader2,
  Pencil,
  Play,
  Plus,
  Save,
  Search,
  Trash2,
  Variable,
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
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
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
import {
  useResolvedApps,
  useCommands,
  useVariables,
} from "@/lib/use-nix-config";
import type {
  ResolvedApp,
  Command,
  Variable as VariableType,
  AppEntity,
} from "@/lib/types";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";

const APP_TYPES = [
  { value: "bun", label: "Bun", color: "bg-yellow-500/20 text-yellow-400" },
  { value: "node", label: "Node.js", color: "bg-green-500/20 text-green-400" },
  { value: "go", label: "Go", color: "bg-cyan-500/20 text-cyan-400" },
  { value: "python", label: "Python", color: "bg-blue-500/20 text-blue-400" },
  { value: "rust", label: "Rust", color: "bg-orange-500/20 text-orange-400" },
  { value: "other", label: "Other", color: "bg-gray-500/20 text-gray-400" },
];

function getTypeColor(type: string): string {
  return (
    APP_TYPES.find((t) => t.value === type)?.color ??
    "bg-gray-500/20 text-gray-400"
  );
}

function getTypeLabel(type: string): string {
  return APP_TYPES.find((t) => t.value === type)?.label ?? type;
}

interface AppFormState {
  name: string;
  description: string;
  path: string;
  type: string;
  port?: number;
  domain?: string;
  commands: string[];
  variables: string[];
}

const defaultFormState: AppFormState = {
  name: "",
  description: "",
  path: "",
  type: "bun",
  commands: [],
  variables: [],
};

/**
 * Component to display linked commands for an app
 */
function AppCommands({ commands }: { commands: Command[] }) {
  const [isOpen, setIsOpen] = useState(false);

  if (commands.length === 0) {
    return (
      <span className="text-muted-foreground text-xs">No commands linked</span>
    );
  }

  return (
    <div>
      <Button
        variant="ghost"
        size="sm"
        className="h-auto gap-1 p-1 text-xs"
        onClick={() => setIsOpen(!isOpen)}
      >
        {isOpen ? (
          <ChevronDown className="h-3 w-3" />
        ) : (
          <ChevronRight className="h-3 w-3" />
        )}
        <Play className="h-3 w-3 text-accent" />
        <span>
          {commands.length} command{commands.length !== 1 ? "s" : ""}
        </span>
      </Button>
      {isOpen && (
        <div className="mt-2 space-y-1">
          {commands.map((cmd) => (
            <div
              key={cmd.id}
              className="flex items-center gap-2 rounded-md bg-secondary/50 px-2 py-1 text-xs"
            >
              <Play className="h-3 w-3 text-muted-foreground" />
              <span className="font-medium">{cmd.name}</span>
              <span className="text-muted-foreground">({cmd.category})</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/**
 * Component to display linked variables for an app
 */
function AppVariables({ variables }: { variables: VariableType[] }) {
  const [isOpen, setIsOpen] = useState(false);

  if (variables.length === 0) {
    return (
      <span className="text-muted-foreground text-xs">No variables linked</span>
    );
  }

  const secretCount = variables.filter((v) => v.type === "secret").length;

  return (
    <div>
      <Button
        variant="ghost"
        size="sm"
        className="h-auto gap-1 p-1 text-xs"
        onClick={() => setIsOpen(!isOpen)}
      >
        {isOpen ? (
          <ChevronDown className="h-3 w-3" />
        ) : (
          <ChevronRight className="h-3 w-3" />
        )}
        <Variable className="h-3 w-3 text-accent" />
        <span>
          {variables.length} variable{variables.length !== 1 ? "s" : ""}
          {secretCount > 0 && (
            <span className="ml-1 text-yellow-400">
              ({secretCount} secret{secretCount !== 1 ? "s" : ""})
            </span>
          )}
        </span>
      </Button>
      {isOpen && (
        <div className="mt-2 space-y-1">
          {variables.map((variable) => (
            <div
              key={variable.id}
              className="flex items-center gap-2 rounded-md bg-secondary/50 px-2 py-1 text-xs"
            >
              <Variable className="h-3 w-3 text-muted-foreground" />
              <code className="font-mono">{variable.name}</code>
              <Badge
                variant="outline"
                className={
                  variable.type === "secret"
                    ? "border-yellow-500/30 text-yellow-400"
                    : "border-border"
                }
              >
                {variable.type}
              </Badge>
              {variable.sensitive && <span className="text-yellow-400">●</span>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/**
 * Command/Variable selector for the edit form
 */
function MultiSelect({
  label,
  items,
  selectedIds,
  onSelectionChange,
  renderItem,
}: {
  label: string;
  items: { id: string; name: string }[];
  selectedIds: string[];
  onSelectionChange: (ids: string[]) => void;
  renderItem: (item: { id: string; name: string }) => React.ReactNode;
}) {
  const toggleItem = (id: string) => {
    if (selectedIds.includes(id)) {
      onSelectionChange(selectedIds.filter((i) => i !== id));
    } else {
      onSelectionChange([...selectedIds, id]);
    }
  };

  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border border-border bg-secondary/30 p-2">
        {items.length === 0 ? (
          <p className="py-2 text-center text-muted-foreground text-xs">
            No {label.toLowerCase()} available
          </p>
        ) : (
          items.map((item) => (
            <div
              key={item.id}
              className="flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-secondary/50"
            >
              <Checkbox
                id={`select-${item.id}`}
                checked={selectedIds.includes(item.id)}
                onCheckedChange={() => toggleItem(item.id)}
              />
              <label
                htmlFor={`select-${item.id}`}
                className="flex-1 cursor-pointer text-sm"
              >
                {renderItem(item)}
              </label>
            </div>
          ))
        )}
      </div>
      {selectedIds.length > 0 && (
        <p className="text-muted-foreground text-xs">
          {selectedIds.length} selected
        </p>
      )}
    </div>
  );
}

export function AppsPanel() {
  const { token } = useAgentContext();
  const { data: resolvedApps, isLoading, error, refetch } = useResolvedApps();
  const { data: allCommands } = useCommands();
  const { data: allVariables } = useVariables();

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedType, setSelectedType] = useState<string | null>(null);
  const [editingApp, setEditingApp] = useState<string | null>(null);
  const [formState, setFormState] = useState<AppFormState>(defaultFormState);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [newAppId, setNewAppId] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  // Convert commands and variables to selectable items
  const commandItems = useMemo(() => {
    if (!allCommands) return [];
    return Object.entries(allCommands).map(([id, cmd]) => ({
      id,
      name: cmd.name,
      category: cmd.category,
    }));
  }, [allCommands]);

  const variableItems = useMemo(() => {
    if (!allVariables) return [];
    return Object.entries(allVariables).map(([id, v]) => ({
      id,
      name: v.name,
      type: v.type,
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

  const handleEdit = (appId: string, app: ResolvedApp) => {
    setEditingApp(appId);
    setFormState({
      name: app.name,
      description: app.description ?? "",
      path: app.path,
      type: app.type ?? "other",
      port: app.port,
      domain: app.domain,
      commands: app.commands.map((c) => c.id!).filter(Boolean),
      variables: app.variables.map((v) => v.id!).filter(Boolean),
    });
  };

  const handleSave = async (appId: string) => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const appsClient = client.mapEntity<AppEntity>("apps");

      // Update the specific app
      const updatedApp: AppEntity = {
        name: formState.name,
        description: formState.description || undefined,
        path: formState.path,
        type: formState.type || undefined,
        port: formState.port,
        domain: formState.domain || undefined,
        commands:
          formState.commands.length > 0 ? formState.commands : undefined,
        variables:
          formState.variables.length > 0 ? formState.variables : undefined,
      };

      await appsClient.set(appId, updatedApp);
      toast.success(`Updated app "${appId}"`);
      setEditingApp(null);
      setFormState(defaultFormState);
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save app");
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancel = () => {
    setEditingApp(null);
    setFormState(defaultFormState);
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
      const appsClient = client.mapEntity<AppEntity>("apps");

      await appsClient.remove(appId);
      toast.success(`Deleted app "${appId}"`);
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to delete app");
    } finally {
      setIsDeleting(false);
    }
  };

  const handleAddApp = async () => {
    if (!newAppId.trim() || !token) {
      toast.error(!token ? "Not connected to agent" : "Please enter an app ID");
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const appsClient = client.mapEntity<AppEntity>("apps");

      const exists = await appsClient.has(newAppId);
      if (exists) {
        toast.error(`App "${newAppId}" already exists`);
        setIsSaving(false);
        return;
      }

      const newApp: AppEntity = {
        name: formState.name || newAppId,
        description: formState.description || undefined,
        path: formState.path || `apps/${newAppId}`,
        type: formState.type || "bun",
        port: formState.port,
        domain: formState.domain || undefined,
        commands:
          formState.commands.length > 0 ? formState.commands : undefined,
        variables:
          formState.variables.length > 0 ? formState.variables : undefined,
      };

      await appsClient.set(newAppId, newApp);
      toast.success(`Created app "${newAppId}"`);
      setDialogOpen(false);
      setNewAppId("");
      setFormState(defaultFormState);
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to create app");
    } finally {
      setIsSaving(false);
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
              Manage your monorepo apps with linked commands and variables
            </p>
          </div>

          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <Button
              className="gap-2"
              onClick={() => {
                setFormState(defaultFormState);
                setNewAppId("");
                setDialogOpen(true);
              }}
              disabled={!token}
            >
              <Plus className="h-4 w-4" />
              Add App
            </Button>
            <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
              <DialogHeader>
                <DialogTitle>Add New App</DialogTitle>
                <DialogDescription>
                  Create a new app and link commands and variables to it.
                </DialogDescription>
              </DialogHeader>
              <div className="grid gap-4 py-4">
                <div className="grid gap-2">
                  <Label htmlFor="new-app-id">App ID *</Label>
                  <Input
                    id="new-app-id"
                    placeholder="e.g., web, api, mobile"
                    value={newAppId}
                    onChange={(e) => setNewAppId(e.target.value)}
                  />
                  <p className="text-muted-foreground text-xs">
                    Unique identifier for this app
                  </p>
                </div>

                <div className="grid gap-2">
                  <Label htmlFor="new-app-name">Display Name</Label>
                  <Input
                    id="new-app-name"
                    placeholder="e.g., Web Frontend"
                    value={formState.name}
                    onChange={(e) =>
                      setFormState((s) => ({ ...s, name: e.target.value }))
                    }
                  />
                </div>

                <div className="grid gap-2">
                  <Label htmlFor="new-app-description">Description</Label>
                  <Input
                    id="new-app-description"
                    placeholder="Brief description of the app"
                    value={formState.description}
                    onChange={(e) =>
                      setFormState((s) => ({
                        ...s,
                        description: e.target.value,
                      }))
                    }
                  />
                </div>

                <div className="grid gap-2">
                  <Label htmlFor="new-app-path">Path *</Label>
                  <Input
                    id="new-app-path"
                    placeholder="apps/web"
                    value={formState.path}
                    onChange={(e) =>
                      setFormState((s) => ({ ...s, path: e.target.value }))
                    }
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="grid gap-2">
                    <Label htmlFor="new-app-type">Type</Label>
                    <Select
                      value={formState.type}
                      onValueChange={(value) =>
                        setFormState((s) => ({ ...s, type: value }))
                      }
                    >
                      <SelectTrigger id="new-app-type">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {APP_TYPES.map((type) => (
                          <SelectItem key={type.value} value={type.value}>
                            {type.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="grid gap-2">
                    <Label htmlFor="new-app-port">Dev Port</Label>
                    <Input
                      id="new-app-port"
                      type="number"
                      placeholder="3000"
                      value={formState.port ?? ""}
                      onChange={(e) =>
                        setFormState((s) => ({
                          ...s,
                          port: e.target.value
                            ? Number(e.target.value)
                            : undefined,
                        }))
                      }
                    />
                  </div>
                </div>

                <div className="grid gap-2">
                  <Label htmlFor="new-app-domain">Local Domain</Label>
                  <Input
                    id="new-app-domain"
                    placeholder="app.local"
                    value={formState.domain ?? ""}
                    onChange={(e) =>
                      setFormState((s) => ({ ...s, domain: e.target.value }))
                    }
                  />
                </div>

                <MultiSelect
                  label="Commands"
                  items={commandItems}
                  selectedIds={formState.commands}
                  onSelectionChange={(ids) =>
                    setFormState((s) => ({ ...s, commands: ids }))
                  }
                  renderItem={(item) => (
                    <span className="flex items-center gap-2">
                      <Play className="h-3 w-3 text-muted-foreground" />
                      {item.name}
                    </span>
                  )}
                />

                <MultiSelect
                  label="Variables"
                  items={variableItems}
                  selectedIds={formState.variables}
                  onSelectionChange={(ids) =>
                    setFormState((s) => ({ ...s, variables: ids }))
                  }
                  renderItem={(item) => (
                    <span className="flex items-center gap-2">
                      <Variable className="h-3 w-3 text-muted-foreground" />
                      <code className="font-mono text-xs">{item.name}</code>
                    </span>
                  )}
                />
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>
                  Cancel
                </Button>
                <Button
                  onClick={handleAddApp}
                  disabled={
                    !newAppId.trim() || !formState.path.trim() || isSaving
                  }
                >
                  {isSaving && (
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  )}
                  Add App
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
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
                        <div className="grid gap-4 sm:grid-cols-2">
                          <div className="grid gap-2">
                            <Label htmlFor={`${appId}-name`}>Name</Label>
                            <Input
                              id={`${appId}-name`}
                              value={formState.name}
                              onChange={(e) =>
                                setFormState((s) => ({
                                  ...s,
                                  name: e.target.value,
                                }))
                              }
                            />
                          </div>
                          <div className="grid gap-2">
                            <Label htmlFor={`${appId}-type`}>Type</Label>
                            <Select
                              value={formState.type}
                              onValueChange={(value) =>
                                setFormState((s) => ({ ...s, type: value }))
                              }
                            >
                              <SelectTrigger id={`${appId}-type`}>
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                {APP_TYPES.map((type) => (
                                  <SelectItem
                                    key={type.value}
                                    value={type.value}
                                  >
                                    {type.label}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>

                        <div className="grid gap-2">
                          <Label htmlFor={`${appId}-description`}>
                            Description
                          </Label>
                          <Input
                            id={`${appId}-description`}
                            value={formState.description}
                            onChange={(e) =>
                              setFormState((s) => ({
                                ...s,
                                description: e.target.value,
                              }))
                            }
                          />
                        </div>

                        <div className="grid gap-2">
                          <Label htmlFor={`${appId}-path`}>Path</Label>
                          <Input
                            id={`${appId}-path`}
                            value={formState.path}
                            onChange={(e) =>
                              setFormState((s) => ({
                                ...s,
                                path: e.target.value,
                              }))
                            }
                          />
                        </div>

                        <div className="grid gap-4 sm:grid-cols-2">
                          <div className="grid gap-2">
                            <Label htmlFor={`${appId}-port`}>Dev Port</Label>
                            <Input
                              id={`${appId}-port`}
                              type="number"
                              value={formState.port ?? ""}
                              onChange={(e) =>
                                setFormState((s) => ({
                                  ...s,
                                  port: e.target.value
                                    ? Number(e.target.value)
                                    : undefined,
                                }))
                              }
                            />
                          </div>
                          <div className="grid gap-2">
                            <Label htmlFor={`${appId}-domain`}>
                              Local Domain
                            </Label>
                            <Input
                              id={`${appId}-domain`}
                              value={formState.domain ?? ""}
                              onChange={(e) =>
                                setFormState((s) => ({
                                  ...s,
                                  domain: e.target.value,
                                }))
                              }
                            />
                          </div>
                        </div>

                        <MultiSelect
                          label="Commands"
                          items={commandItems}
                          selectedIds={formState.commands}
                          onSelectionChange={(ids) =>
                            setFormState((s) => ({ ...s, commands: ids }))
                          }
                          renderItem={(item) => (
                            <span className="flex items-center gap-2">
                              <Play className="h-3 w-3 text-muted-foreground" />
                              {item.name}
                            </span>
                          )}
                        />

                        <MultiSelect
                          label="Variables"
                          items={variableItems}
                          selectedIds={formState.variables}
                          onSelectionChange={(ids) =>
                            setFormState((s) => ({ ...s, variables: ids }))
                          }
                          renderItem={(item) => (
                            <span className="flex items-center gap-2">
                              <Variable className="h-3 w-3 text-muted-foreground" />
                              <code className="font-mono text-xs">
                                {item.name}
                              </code>
                            </span>
                          )}
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

                        {/* Linked commands and variables */}
                        <div className="flex flex-wrap gap-4 border-t border-border pt-4">
                          <AppCommands commands={app.commands} />
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
