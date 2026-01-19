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
  /** Initial project ID (e.g., from URL params) */
  initialProjectId?: string;
}

export function ProjectProvider({
  children,
  initialProjectId,
}: ProjectProviderProps) {
  const { isConnected } = useAgentContext();
  const agentClient = useAgentClient();

  const [projects, setProjects] = useState<Project[]>([]);
  const [currentProjectId, setCurrentProjectId] = useState<string | null>(
    initialProjectId ?? null,
  );
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

      // If no current project set, use default or first active
      if (!currentProjectId && projectList.length > 0) {
        const defaultProj = projectList.find((p) => p.is_default);
        const activeProj = projectList.find((p) => p.active);
        const firstProj = projectList[0];
        const autoProject = defaultProj ?? activeProj ?? firstProj;
        if (autoProject?.id) {
          setCurrentProjectId(autoProject.id);
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      setIsLoading(false);
    }
  }, [isConnected, agentClient, currentProjectId]);

  // Load projects when connected
  useEffect(() => {
    if (isConnected) {
      refreshProjects();
    }
  }, [isConnected, refreshProjects]);

  // Update agent client when project changes
  useEffect(() => {
    if (currentProjectId) {
      agentClient.setProjectId(currentProjectId);
    }
  }, [currentProjectId, agentClient]);

  // Handle initial project ID from props (e.g., URL change)
  useEffect(() => {
    if (initialProjectId && initialProjectId !== currentProjectId) {
      setCurrentProjectId(initialProjectId);
    }
  }, [initialProjectId, currentProjectId]);

  const currentProject = useMemo(() => {
    if (!currentProjectId) return null;
    return (
      projects.find(
        (p) =>
          p.id === currentProjectId ||
          p.name.toLowerCase() === currentProjectId.toLowerCase() ||
          p.path === currentProjectId,
      ) ?? null
    );
  }, [projects, currentProjectId]);

  const defaultProject = useMemo(() => {
    return projects.find((p) => p.is_default) ?? null;
  }, [projects]);

  const getProject = useCallback(
    (id: string) => {
      return projects.find(
        (p) =>
          p.id === id ||
          p.name.toLowerCase() === id.toLowerCase() ||
          p.path === id,
      );
    },
    [projects],
  );

  const setCurrentProject = useCallback((identifier: string) => {
    setCurrentProjectId(identifier);
  }, []);

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

  return (
    <ProjectContext.Provider value={value}>{children}</ProjectContext.Provider>
  );
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
