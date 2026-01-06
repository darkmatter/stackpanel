"use client";

import { Check, FolderOpen, Loader2, Plus } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
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
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useAgentContext } from "@/lib/agent-provider";
import { useTRPC } from "@/utils/trpc";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

const ADD_PROJECT_VALUE = "__add_project__";

export function ProjectSelector() {
  const { host, port, token, healthStatus } = useAgentContext();
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [newProjectPath, setNewProjectPath] = useState("");
  const [validationError, setValidationError] = useState<string | null>(null);

  const trpc = useTRPC();
  const queryClient = useQueryClient();

  // Query for listing projects (public endpoint)
  const projectsQuery = useQuery(
    trpc.agent.listProjects.queryOptions(
      { host, port },
      {
        enabled: healthStatus === "available",
        staleTime: 5000,
      },
    ),
  );

  // Query for current project (public endpoint)
  const currentProjectQuery = useQuery(
    trpc.agent.currentProject.queryOptions(
      { host, port },
      {
        enabled: healthStatus === "available",
        staleTime: 5000,
      },
    ),
  );

  // Mutation for opening a project
  const openProjectMutation = useMutation(
    trpc.agent.openProject.mutationOptions({
      onSuccess: (data) => {
        toast.success(`Opened project: ${data.project.name}`);
        queryClient.invalidateQueries({
          queryKey: trpc.agent.listProjects.queryKey(),
        });
        queryClient.invalidateQueries({
          queryKey: trpc.agent.currentProject.queryKey(),
        });
      },
      onError: (error) => {
        toast.error(error.message || "Failed to open project");
      },
    }),
  );

  // Mutation for validating a project
  const validateProjectMutation = useMutation(
    trpc.agent.validateProject.mutationOptions(),
  );

  const projects = projectsQuery.data ?? [];
  const currentProject = currentProjectQuery.data?.has_project
    ? currentProjectQuery.data.project
    : null;
  const isLoading = projectsQuery.isLoading || currentProjectQuery.isLoading;
  const isOpening = openProjectMutation.isPending;

  const handleSelectProject = async (value: string) => {
    if (value === ADD_PROJECT_VALUE) {
      setAddDialogOpen(true);
      return;
    }

    if (!value || value === currentProject?.path || !token) return;

    openProjectMutation.mutate({
      path: value,
      token,
      host,
      port,
    });
  };

  const handleAddProject = async () => {
    if (!newProjectPath.trim()) {
      setValidationError("Please enter a project path");
      return;
    }

    if (!token) {
      setValidationError("You must pair with the agent first");
      return;
    }

    setValidationError(null);

    try {
      // First validate the project
      const validateResult = await validateProjectMutation.mutateAsync({
        path: newProjectPath.trim(),
        token,
        host,
        port,
      });

      if (!validateResult.valid) {
        setValidationError(validateResult.message ?? "Invalid project path");
        return;
      }

      // Now open the project
      await openProjectMutation.mutateAsync({
        path: newProjectPath.trim(),
        token,
        host,
        port,
      });

      setAddDialogOpen(false);
      setNewProjectPath("");
    } catch (err) {
      setValidationError(
        err instanceof Error ? err.message : "Failed to add project",
      );
    }
  };

  if (healthStatus !== "available") {
    return null;
  }

  return (
    <>
      <Select
        disabled={isLoading || isOpening || !token}
        onValueChange={handleSelectProject}
        value={currentProject?.path ?? ""}
      >
        <SelectTrigger className="w-[220px] bg-secondary/50">
          {isLoading || isOpening ? (
            <div className="flex items-center gap-2">
              <Loader2 className="h-4 w-4 animate-spin" />
              <span className="text-muted-foreground">
                {isOpening ? "Opening..." : "Loading..."}
              </span>
            </div>
          ) : currentProject ? (
            <div className="flex items-center gap-2">
              <FolderOpen className="h-4 w-4 text-accent" />
              <span className="truncate">{currentProject.name}</span>
              {!token && (
                <span className="text-muted-foreground text-xs">
                  (pair to change)
                </span>
              )}
            </div>
          ) : !token ? (
            <div className="flex items-center gap-2 text-muted-foreground">
              <FolderOpen className="h-4 w-4" />
              <span>Pair to select project</span>
            </div>
          ) : (
            <SelectValue placeholder="Select a project" />
          )}
        </SelectTrigger>
        <SelectContent>
          {projects.length === 0 ? (
            <div className="px-2 py-4 text-center text-muted-foreground text-sm">
              No projects yet
            </div>
          ) : (
            projects.map((project) => (
              <SelectItem key={project.path} value={project.path}>
                <div className="flex w-full items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <FolderOpen className="h-4 w-4" />
                    <div className="flex flex-col">
                      <span>{project.name}</span>
                      <span className="max-w-[180px] truncate text-muted-foreground text-xs">
                        {project.path}
                      </span>
                    </div>
                  </div>
                  {project.active && <Check className="h-4 w-4 text-accent" />}
                </div>
              </SelectItem>
            ))
          )}
          <SelectSeparator />
          <SelectItem value={ADD_PROJECT_VALUE}>
            <div className="flex items-center gap-2 text-accent">
              <Plus className="h-4 w-4" />
              <span>Add project...</span>
            </div>
          </SelectItem>
        </SelectContent>
      </Select>

      <Dialog onOpenChange={setAddDialogOpen} open={addDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add Project</DialogTitle>
            <DialogDescription>
              Enter the path to a Stackpanel project directory. The directory
              must be a git repository with a valid Stackpanel configuration.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-2">
              <Label htmlFor="project-path">Project Path</Label>
              <Input
                className="font-mono"
                id="project-path"
                onChange={(e) => {
                  setNewProjectPath(e.target.value);
                  setValidationError(null);
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    handleAddProject();
                  }
                }}
                placeholder="/path/to/your/project"
                value={newProjectPath}
              />
              {validationError && (
                <p className="text-destructive text-sm">{validationError}</p>
              )}
            </div>
            <div className="rounded-lg border border-border bg-secondary/30 p-3">
              <p className="text-muted-foreground text-sm">
                A valid Stackpanel project must have:
              </p>
              <ul className="mt-2 list-inside list-disc text-muted-foreground text-sm">
                <li>
                  A <code className="text-foreground">.git</code> directory
                </li>
                <li>
                  A <code className="text-foreground">flake.nix</code> with
                  Stackpanel config, or a{" "}
                  <code className="text-foreground">.stackpanel</code> directory
                </li>
              </ul>
            </div>
          </div>
          <DialogFooter>
            <Button
              onClick={() => {
                setAddDialogOpen(false);
                setNewProjectPath("");
                setValidationError(null);
              }}
              variant="outline"
            >
              Cancel
            </Button>
            <Button
              className="bg-accent text-accent-foreground hover:bg-accent/90"
              disabled={
                openProjectMutation.isPending ||
                validateProjectMutation.isPending
              }
              onClick={handleAddProject}
            >
              {(openProjectMutation.isPending ||
                validateProjectMutation.isPending) && (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              )}
              Add Project
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

/**
 * Compact project indicator for headers/sidebars
 */
export function ProjectIndicator() {
  const { host, port, healthStatus } = useAgentContext();
  const trpc = useTRPC();

  const currentProjectQuery = useQuery(
    trpc.agent.currentProject.queryOptions(
      { host, port },
      {
        enabled: healthStatus === "available",
        staleTime: 5000,
        refetchInterval: 5000,
      },
    ),
  );

  const currentProject = currentProjectQuery.data?.has_project
    ? currentProjectQuery.data.project
    : null;

  if (!currentProject) {
    return (
      <div className="flex items-center gap-2 text-muted-foreground text-xs">
        <FolderOpen className="h-3 w-3" />
        <span>No project</span>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2 text-foreground text-xs">
      <FolderOpen className="h-3 w-3 text-accent" />
      <span className="max-w-[120px] truncate">{currentProject.name}</span>
    </div>
  );
}
