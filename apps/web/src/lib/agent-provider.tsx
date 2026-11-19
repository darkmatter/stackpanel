"use client";

import { createClient } from "@connectrpc/connect";
import { TransportProvider, useTransport } from "@connectrpc/connect-query";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { useQueryClient } from "@tanstack/react-query";
import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { AgentHttpClient } from "./agent";
import { createAgentTransport } from "./connect-transport";
import { canonicalAgentOrigin, tokenAgentId, type AgentCredential } from "./agent-identity";
import { useInitialAgentProject } from "./use-agent-project";
import { useAgentSession } from "./use-agent-session";
import type { FileContent } from "./types";

type AgentProviderProps = {
  children: ReactNode;
  host?: string;
  port?: number;
  credential?: AgentCredential | null;
  requestedProjectId?: string;
};

type AgentContextValue = {
  host: string;
  port: number;
  healthStatus: "checking" | "available" | "unavailable";
  projectRoot: string | null;
  /** Immutable project for scoped requests, or null until one is known. */
  selectedProjectId: string | null;
  selectProject: (projectId: string) => void;
  token: string | null;
  isConnected: boolean;
  isAuthenticated: boolean;
  isPairing: boolean;
  pairingError: string | null;
  isConnecting: boolean;
  error: Error | null;
  pair: () => void;
  clearPairing: () => void;
  connect: () => Promise<void>;
  disconnect: () => void;
  exec: (command: string, args?: string[]) => Promise<unknown>;
  nixEval: <T = unknown>(expression: string) => Promise<T>;
  nixGenerate: () => Promise<unknown>;
  readFile: (path: string) => Promise<FileContent>;
  writeFile: (path: string, content: string) => Promise<void>;
  setSecret: (env: "dev" | "staging" | "prod", key: string, value: string) => Promise<unknown>;
};

const AgentContext = createContext<AgentContextValue | null>(null);

export function AgentProvider({ host = "localhost", port = 9876, ...props }: AgentProviderProps) {
  // Synchronously isolate state and cancel the old session on endpoint changes,
  // including callers that rerender this provider without a React key.
  const origin = canonicalAgentOrigin(host, port);
  return (
    <AgentSessionProvider
      key={origin}
      {...props}
      host={new URL(origin).hostname}
      port={port}
      origin={origin}
    />
  );
}

function AgentSessionProvider({
  children,
  host,
  port,
  origin,
  credential,
  requestedProjectId: requested,
}: AgentProviderProps & { origin: string; host: string; port: number }) {
  const requestedProjectId = requested?.trim();
  const session = useAgentSession(origin, credential?.origin === origin ? credential.token : null);
  const { token, projectRoot } = session;
  const queryClient = useQueryClient();
  const projectStorageKey = `stackpanel.agent.project:${host}:${port}`;
  const [tabProject, setSelectedProjectId] = useState<string | null>(() =>
    typeof window === "undefined"
      ? null
      : sessionStorage.getItem(projectStorageKey)?.trim() || null,
  );
  const selectedProjectId = requestedProjectId || tabProject;
  useEffect(() => {
    if (requestedProjectId) {
      setSelectedProjectId(requestedProjectId);
      sessionStorage.setItem(projectStorageKey, requestedProjectId);
    }
  }, [requestedProjectId, projectStorageKey]);
  const transport = useMemo(
    () => createAgentTransport(token, host, port, selectedProjectId),
    [token, host, port, selectedProjectId],
  );

  const selectProject = useCallback(
    (id: string) => {
      const projectId = id.trim();
      if (!projectId || projectId === selectedProjectId) return;
      sessionStorage.setItem(projectStorageKey, projectId);
      setSelectedProjectId(projectId);
      // Queries outside connect-query (the AgentService and REST hooks) are
      // keyed without the project and act on the agent's current project, so
      // drop their data rather than show the previous project's on refetch.
      void queryClient.resetQueries({
        predicate: (query) =>
          query.queryKey[0] !== "connect-query" && query.queryKey[1] !== "initial-project",
      });
    },
    [projectStorageKey, queryClient, selectedProjectId],
  );

  const discoveryError = useInitialAgentProject({
    transport,
    host,
    port,
    agentId: token ? tokenAgentId(token) : null,
    root: projectRoot,
    selected: selectedProjectId,
    select: selectProject,
  });
  const client = useMemo(
    () =>
      new AgentHttpClient({
        host,
        port,
        token: token ?? undefined,
        requireAuth: true,
        projectId: selectedProjectId ?? undefined,
      }),
    [host, port, token, selectedProjectId],
  );
  const actions = useMemo(
    () => ({
      exec: (command: string, args?: string[]) => client.exec({ command, args }),
      nixEval: <T,>(expression: string) => client.nixEval<T>(expression),
      nixGenerate: () => client.nixGenerate(),
      readFile: (path: string) => client.readFile(path),
      writeFile: (path: string, content: string) => client.writeFile(path, content),
      setSecret: (env: "dev" | "staging" | "prod", key: string, value: string) =>
        client.setSecret({ env, key, value }),
    }),
    [client],
  );
  const value: AgentContextValue = {
    ...session,
    ...actions,
    host,
    port,
    selectedProjectId,
    selectProject,
    isAuthenticated: !!token,
    isConnected: !!token,
    isConnecting: session.healthStatus === "checking",
    error: session.pairingError ? new Error(session.pairingError) : discoveryError,
    connect: async () => session.pair(),
    disconnect: session.clearPairing,
  };

  return (
    <AgentContext.Provider value={value}>
      <TransportProvider transport={transport}>{children}</TransportProvider>
    </AgentContext.Provider>
  );
}

export function useAgentContext(): AgentContextValue {
  const ctx = useContext(AgentContext);
  if (!ctx) {
    throw new Error("useAgentContext must be used within <AgentProvider>");
  }
  return ctx;
}

/**
 * Hook to get a shared AgentHttpClient instance.
 * Uses the host, port, and token from the AgentProvider context.
 */
export function useAgentClient(): AgentHttpClient {
  const { host, port, token, selectedProjectId } = useAgentContext();
  return useMemo(
    () =>
      new AgentHttpClient({
        host,
        port,
        token: token ?? undefined,
        requireAuth: true,
        projectId: selectedProjectId ?? undefined,
      }),
    [host, port, token, selectedProjectId],
  );
}

/** Uses the same authenticated, project-scoped transport for unary calls and streams. */
export function useModuleServiceClient() {
  const { isAuthenticated, selectedProjectId } = useAgentContext();
  const transport = useTransport();
  return useMemo(
    () =>
      isAuthenticated && selectedProjectId?.trim() ? createClient(ModuleService, transport) : null,
    [isAuthenticated, selectedProjectId, transport],
  );
}
