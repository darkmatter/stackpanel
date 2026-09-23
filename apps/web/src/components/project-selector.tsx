"use client";

import { ConnectError } from "@connectrpc/connect";
import {
  createConnectQueryKey,
  useMutation as useConnectMutation,
  useQuery as useConnectQuery,
  useTransport,
} from "@connectrpc/connect-query";
import { ProjectService } from "@stackpanel/proto/agent/v1/project";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { Button } from "@ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Badge } from "@ui/badge";
import { Check, FolderOpen, Loader2, LogOut, Plus } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useAgentEndpoint } from "@/lib/agent-endpoint";
import { useAgentClient, useAgentContext } from "@/lib/agent-provider";

const ADD_PROJECT_VALUE = "__add_project__";

interface ProjectSelectorProps {
  variant?: "default" | "sidebar";
}

export function ProjectSelector(_props: ProjectSelectorProps) {
  const { host, port, token, healthStatus, isAuthenticated } = useAgentContext();
  const agentClient = useAgentClient();
  const transport = useTransport();
  const { isDemo, useLocal } = useAgentEndpoint();
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [newProjectPath, setNewProjectPath] = useState("");
  const [validationError, setValidationError] = useState<string | null>(null);
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // The project registry comes from the agent's v1 ProjectService, called
  // from the browser. The demo stays off the network: it has one synthetic
  // project and renders a badge instead of the picker.
  const projectsQuery = useConnectQuery(
    ProjectService.method.listProjects,
    {},
    { enabled: isAuthenticated && !isDemo, staleTime: 5000 },
  );
  const listProjectsKey = createConnectQueryKey({
    schema: ProjectService.method.listProjects,
    transport,
    cardinality: "finite",
  });

  // The rest of the Studio still runs against the agent's single current
  // project, so reading and switching it stays on REST until requests select
  // their project (ADR 0005, stackpanel-thq.8.1).
  const currentProjectKey = ["agent", "project", "current", host, port];
  const currentProjectQuery = useQuery({
    queryKey: currentProjectKey,
    queryFn: () => agentClient.getCurrentProject(),
    enabled: !isDemo && healthStatus === "available",
    staleTime: 5000,
  });

  const openProjectMutation = useMutation({
    mutationFn: (path: string) => agentClient.openProject(path),
    onSuccess: ({ project }) => {
      toast.success(`Opened project: ${project.name}`);
      void queryClient.invalidateQueries({ queryKey: listProjectsKey });
      void queryClient.invalidateQueries({ queryKey: currentProjectKey });
      if (project.id) {
        void navigate({
          to: "/studio",
          search: { project: project.id },
        });
      }
    },
    onError: (error) => {
      toast.error(error.message || "Failed to open project");
    },
  });

  // AddProject validates the directory and fails with InvalidArgument, and a
  // message saying why, when it is not a stackpanel project.
  const addProjectMutation = useConnectMutation(ProjectService.method.addProject, {
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: listProjectsKey });
    },
  });

  const projects = projectsQuery.data?.projects ?? [];
  const defaultProjectId = projectsQuery.data?.defaultProjectId;
  const currentProject = currentProjectQuery.data?.project ?? null;
  const isLoading = projectsQuery.isLoading || currentProjectQuery.isLoading;
  const isOpening = openProjectMutation.isPending;
  const isAdding = addProjectMutation.isPending || openProjectMutation.isPending;

  const handleSelectProject = (path: string) => {
    if (path === ADD_PROJECT_VALUE) {
      setAddDialogOpen(true);
      return;
    }

    const selectedProject = projects.find((p) => p.path === path);
    if (!selectedProject?.valid || selectedProject.path === currentProject?.path) return;

    openProjectMutation.mutate(selectedProject.path);
  };

  const closeAddDialog = () => {
    setAddDialogOpen(false);
    setNewProjectPath("");
    setValidationError(null);
  };

  const handleAddProject = async () => {
    const path = newProjectPath.trim();
    if (!path) {
      setValidationError("Please enter a project path");
      return;
    }

    setValidationError(null);

    try {
      const { project } = await addProjectMutation.mutateAsync({ path });
      await openProjectMutation.mutateAsync(project?.path ?? path);
      closeAddDialog();
    } catch (err) {
      setValidationError(
        err instanceof ConnectError
          ? err.rawMessage
          : err instanceof Error
            ? err.message
            : "Failed to add project",
      );
    }
  };

  if (isDemo) {
    return (
      <div className="flex items-center gap-2 rounded-md border border-amber-500/30 bg-amber-500/[0.06] px-3 py-1.5 text-xs">
        <FolderOpen className="h-3.5 w-3.5 text-amber-400" />
        <span className="font-medium text-amber-100">stackpanel-demo</span>
        <Badge
          variant="outline"
          className="border-amber-500/40 bg-transparent px-1.5 py-0 text-[10px] text-amber-200"
        >
          demo
        </Badge>
        <Button
          size="sm"
          variant="ghost"
          className="h-6 px-1.5 text-amber-200 hover:bg-amber-500/15 hover:text-amber-50"
          onClick={() => useLocal()}
          aria-label="Exit demo mode"
        >
          <LogOut className="h-3 w-3" />
        </Button>
      </div>
    );
  }

  if (healthStatus !== "available") {
    return null;
  }

  return (
    <>
      <Select
        disabled={!isAuthenticated || isLoading || isOpening}
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
          {projectsQuery.error ? (
            <div className="px-2 py-4 text-center text-destructive text-sm">
              Couldn't load projects: {projectsQuery.error.rawMessage}
            </div>
          ) : projects.length === 0 ? (
            <div className="px-2 py-4 text-center text-muted-foreground text-sm">
              No projects yet
            </div>
          ) : (
            projects.map((project) => (
              <SelectItem key={project.id} value={project.path} disabled={!project.valid}>
                <div className="flex w-full items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <FolderOpen className="h-4 w-4 text-primary" />
                    <div className="flex flex-col">
                      <div className="flex items-center gap-2">
                        <span>{project.name}</span>
                        <Badge
                          variant="outline"
                          className="text-[10px]  font-mono px-1 py-0"
                        >
                          {project.id}
                        </Badge>
                        {project.id === defaultProjectId && (
                          <Badge
                            variant="secondary"
                            className="text-[10px] px-1 py-0"
                          >
                            default
                          </Badge>
                        )}
                      </div>
                      <span className="max-w-45 truncate text-primary text-xs">
                        {project.path}
                      </span>
                      {!project.valid && (
                        <span className="max-w-45 truncate text-destructive text-xs">
                          {project.invalidReason}
                        </span>
                      )}
                    </div>
                  </div>
                  {project.path === currentProject?.path && (
                    <Check className="h-4 w-4 text-accent" />
                  )}
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
                    void handleAddProject();
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
            <Button onClick={closeAddDialog} variant="outline">
              Cancel
            </Button>
            <Button
              className="bg-accent text-accent-foreground hover:bg-accent/90"
              disabled={isAdding}
              onClick={handleAddProject}
            >
              {isAdding && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Add Project
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
