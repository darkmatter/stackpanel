/**
 * Example component demonstrating usage of the nix-data layer
 *
 * This shows how to:
 * - Read apps from Nix configuration using TanStack Query
 * - Update an app with optimistic updates
 * - Delete an app
 */

import { useState } from "react";
import { Loader2, Pencil, Plus, Save, Trash2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  useApps,
  useUpdateApp,
  useDeleteApp,
} from "@/lib/nix-data";
import type { App } from "@stackpanel/proto";

/**
 * Form state for editing an app
 */
interface AppFormState {
  name: string;
  path: string;
  installCommand?: string;
  buildCommand?: string;
  startCommand?: string;
}

/**
 * Apps panel demonstrating nix-data usage
 */
export function AppsPanelExample() {
  const [editingApp, setEditingApp] = useState<string | null>(null);
  const [formState, setFormState] = useState<AppFormState>({
    name: "",
    path: "",
  });
  const [dialogOpen, setDialogOpen] = useState(false);
  const [newAppId, setNewAppId] = useState("");

  // Read apps from Nix config
  const { data: appsResult, isLoading, error } = useApps();

  // Mutation hooks
  const updateApp = useUpdateApp({
    onSuccess: () => {
      setEditingApp(null);
      setFormState({ name: "", path: "" });
    },
  });

  const deleteApp = useDeleteApp({
    onSuccess: () => {
      // App deleted successfully
    },
  });

  // Extract apps data
  const apps = appsResult?.data ?? {};

  // Handle starting edit
  const handleEdit = (appId: string, app: App) => {
    setEditingApp(appId);
    setFormState({
      name: app.name,
      path: app.path,
      installCommand: app.installCommand,
      buildCommand: app.buildCommand,
      startCommand: app.startCommand,
    });
  };

  // Handle save
  const handleSave = (appId: string) => {
    updateApp.mutate({
      key: appId,
      data: {
        name: formState.name,
        path: formState.path,
        installCommand: formState.installCommand || undefined,
        buildCommand: formState.buildCommand || undefined,
        startCommand: formState.startCommand || undefined,
      },
    });
  };

  // Handle cancel edit
  const handleCancel = () => {
    setEditingApp(null);
    setFormState({ name: "", path: "" });
  };

  // Handle delete
  const handleDelete = (appId: string) => {
    if (confirm(`Are you sure you want to delete "${appId}"?`)) {
      deleteApp.mutate(appId);
    }
  };

  // Handle add new app
  const handleAddApp = () => {
    if (!newAppId.trim()) return;

    updateApp.mutate({
      key: newAppId,
      data: {
        name: newAppId,
        path: `apps/${newAppId}`,
      },
    });

    setNewAppId("");
    setDialogOpen(false);
  };

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
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="font-semibold text-foreground text-xl">
            Apps (Nix Data Example)
          </h2>
          <p className="text-muted-foreground text-sm">
            Manage your monorepo apps - data stored in Nix configuration
          </p>
        </div>

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogTrigger asChild>
            <Button className="gap-2">
              <Plus className="h-4 w-4" />
              Add App
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add New App</DialogTitle>
              <DialogDescription>
                Create a new app entry in your Nix configuration.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="app-id">App ID</Label>
                <Input
                  id="app-id"
                  placeholder="e.g., web, api, mobile"
                  value={newAppId}
                  onChange={(e) => setNewAppId(e.target.value)}
                />
                <p className="text-muted-foreground text-xs">
                  This will be the key in your apps configuration
                </p>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button onClick={handleAddApp} disabled={!newAppId.trim()}>
                Add App
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {Object.keys(apps).length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">
              No apps configured yet. Add your first app to get started.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {Object.entries(apps).map(([appId, app]) => (
            <Card key={appId}>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">{appId}</CardTitle>
                  {editingApp !== appId && (
                    <div className="flex items-center gap-2">
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => handleEdit(appId, app)}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => handleDelete(appId)}
                        disabled={deleteApp.isPending}
                      >
                        <Trash2 className="h-4 w-4 text-destructive" />
                      </Button>
                    </div>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                {editingApp === appId ? (
                  <div className="space-y-4">
                    <div className="grid gap-2">
                      <Label htmlFor={`${appId}-name`}>Name</Label>
                      <Input
                        id={`${appId}-name`}
                        value={formState.name}
                        onChange={(e) =>
                          setFormState((s) => ({ ...s, name: e.target.value }))
                        }
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor={`${appId}-path`}>Path</Label>
                      <Input
                        id={`${appId}-path`}
                        value={formState.path}
                        onChange={(e) =>
                          setFormState((s) => ({ ...s, path: e.target.value }))
                        }
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor={`${appId}-install`}>
                        Install Command (optional)
                      </Label>
                      <Input
                        id={`${appId}-install`}
                        value={formState.installCommand ?? ""}
                        onChange={(e) =>
                          setFormState((s) => ({
                            ...s,
                            installCommand: e.target.value,
                          }))
                        }
                        placeholder="e.g., bun install"
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor={`${appId}-build`}>
                        Build Command (optional)
                      </Label>
                      <Input
                        id={`${appId}-build`}
                        value={formState.buildCommand ?? ""}
                        onChange={(e) =>
                          setFormState((s) => ({
                            ...s,
                            buildCommand: e.target.value,
                          }))
                        }
                        placeholder="e.g., bun run build"
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor={`${appId}-start`}>
                        Start Command (optional)
                      </Label>
                      <Input
                        id={`${appId}-start`}
                        value={formState.startCommand ?? ""}
                        onChange={(e) =>
                          setFormState((s) => ({
                            ...s,
                            startCommand: e.target.value,
                          }))
                        }
                        placeholder="e.g., bun run dev"
                      />
                    </div>
                    <div className="flex items-center gap-2">
                      <Button
                        onClick={() => handleSave(appId)}
                        disabled={updateApp.isPending}
                        className="gap-2"
                      >
                        {updateApp.isPending ? (
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
                  <div className="space-y-2 text-sm">
                    <div className="flex gap-2">
                      <span className="text-muted-foreground">Name:</span>
                      <span>{app.name}</span>
                    </div>
                    <div className="flex gap-2">
                      <span className="text-muted-foreground">Path:</span>
                      <code className="rounded bg-muted px-1 py-0.5 text-xs">
                        {app.path}
                      </code>
                    </div>
                    {app.installCommand && (
                      <div className="flex gap-2">
                        <span className="text-muted-foreground">Install:</span>
                        <code className="rounded bg-muted px-1 py-0.5 text-xs">
                          {app.installCommand}
                        </code>
                      </div>
                    )}
                    {app.startCommand && (
                      <div className="flex gap-2">
                        <span className="text-muted-foreground">Start:</span>
                        <code className="rounded bg-muted px-1 py-0.5 text-xs">
                          {app.startCommand}
                        </code>
                      </div>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}