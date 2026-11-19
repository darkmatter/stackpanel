"use client";

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { useAgentClient, useAgentContext } from "./agent-provider";
import type { Project } from "./agent";

export type { Project };

interface ProjectContextValue {
  /** Currently selected project ID (from URL or default) */
  currentProjectId: string | null;

  /** Currently selected project details */
  currentProject: Project | null;

  /** All available projects */
  projects: Project[];

  /** Whether projects are being loaded */
  isLoading: boolean;

  /** Error loading projects */
  error: Error | null;

  /** Set the current project by ID, name, or path */
  setCurrentProject: (identifier: string) => void;

  /** Refresh the projects list from the agent */
  refreshProjects: () => Promise<void>;

  /** Get a project by ID */
  getProject: (id: string) => Project | undefined;

  /** The default project (if set) */
  defaultProject: Project | null;
}

const ProjectContext = createContext<ProjectContextValue | null>(null);

interface ProjectProviderProps {
  children: ReactNode;
}

export function ProjectProvider({ children }: ProjectProviderProps) {
  const { isConnected, selectedProjectId: currentProjectId, selectProject } = useAgentContext();
  const agentClient = useAgentClient();

  const [projects, setProjects] = useState<Project[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  // Fetch projects from agent
  const refreshProjects = useCallback(async () => {
    if (!isConnected) return;

    setIsLoading(true);
    setError(null);

    try {
      const response = await agentClient.listProjects();
      const projectList = response.projects;
      setProjects(projectList);
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      setIsLoading(false);
    }
  }, [isConnected, agentClient]);

  // Load projects when connected
  useEffect(() => {
    if (isConnected) {
      refreshProjects();
    }
  }, [isConnected, refreshProjects]);

  const currentProject = useMemo(() => {
    if (!currentProjectId) return null;
    return projects.find((project) => project.id === currentProjectId) ?? null;
  }, [projects, currentProjectId]);

  const defaultProject = useMemo(() => {
    return projects.find((p) => p.is_default) ?? null;
  }, [projects]);

  const getProject = useCallback(
    (id: string) => {
      return projects.find(
        (p) => p.id === id || p.name.toLowerCase() === id.toLowerCase() || p.path === id,
      );
    },
    [projects],
  );

  const setCurrentProject = useCallback(
    (identifier: string) => {
      const project = getProject(identifier);
      if (project?.id) selectProject(project.id);
    },
    [getProject, selectProject],
  );

  const value = useMemo<ProjectContextValue>(
    () => ({
      currentProjectId,
      currentProject,
      projects,
      isLoading,
      error,
      setCurrentProject,
      refreshProjects,
      getProject,
      defaultProject,
    }),
    [
      currentProjectId,
      currentProject,
      projects,
      isLoading,
      error,
      setCurrentProject,
      refreshProjects,
      getProject,
      defaultProject,
    ],
  );

  return <ProjectContext.Provider value={value}>{children}</ProjectContext.Provider>;
}

/**
 * Hook to access the project context
 */
export function useProjectContext(): ProjectContextValue {
  const ctx = useContext(ProjectContext);
  if (!ctx) {
    throw new Error("useProjectContext must be used within <ProjectProvider>");
  }
  return ctx;
}

/**
 * Hook to get the current project
 */
export function useCurrentProject(): Project | null {
  const { currentProject } = useProjectContext();
  return currentProject;
}

/**
 * Hook to get all projects
 */
export function useProjects(): Project[] {
  const { projects } = useProjectContext();
  return projects;
}

/**
 * Hook to get project switching function
 */
export function useSetProject(): (identifier: string) => void {
  const { setCurrentProject } = useProjectContext();
  return setCurrentProject;
}
