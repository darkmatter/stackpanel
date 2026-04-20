/**
 * Consolidated React hooks for type-safe RPC communication with the Stackpanel agent.
 *
 * This is the canonical file for all agent communication hooks.
 * Uses Connect-RPC with proto-generated types - no manual type definitions needed.
 *
 * Migration Guide (from use-nix-config.ts):
 * - useNixConfig() → useNixConfigQuery() or useNixConfig() (compatibility wrapper)
 * - useNixData<T>('entity') → use specific hooks (useApps, useVariables, etc.)
 * - useNixMapData<T>('entity') → use specific hooks with mutations
 * - useTurboPackages() → (still available as re-export)
 *
 * @example
 * ```tsx
 * function Dashboard() {
 *   const { data: apps, isLoading } = useApps();
 *   const { data: sst } = useSSTStatus();
 *
 *   if (isLoading) return <Spinner />;
 *
 *   return (
 *     <div>
 *       <h1>Apps: {Object.keys(apps?.apps ?? {}).length}</h1>
 *       <p>SST Deployed: {sst?.deployed ? 'Yes' : 'No'}</p>
 *     </div>
 *   );
 * }
 * ```
 */

import { createClient } from "@connectrpc/connect";
import { AgentService } from "@stackpanel/proto/agent-service";
import type {
  Apps,
  Variables,
  Users,
  Config,
  Secrets,
  Aws,
} from "@stackpanel/proto";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { flattenConfiguredAppVariables } from "./app-env";
import { useAgentContext, useAgentClient } from "./agent-provider";
import { createAgentTransport } from "./connect-transport";
import { useAgentSSEEvent } from "./agent-sse-provider";
import { AgentHttpClient, type AppVariableLinks } from "./agent";
import type { RecipientListResponse, RekeyWorkflowStatus } from "./types";

// =============================================================================
// Query Keys
// =============================================================================

/**
 * Centralized query key management for cache invalidation.
 */
export const agentQueryKeys = {
  // Base keys
  all: ["agent"] as const,

  // Project
  project: () => [...agentQueryKeys.all, "project"] as const,

  // Identity & KMS
  ageIdentity: () => [...agentQueryKeys.all, "ageIdentity"] as const,
  sopsAgeKeysStatus: () => [...agentQueryKeys.all, "sopsAgeKeysStatus"] as const,
  kmsConfig: () => [...agentQueryKeys.all, "kmsConfig"] as const,

  // Entity CRUD
  config: () => [...agentQueryKeys.all, "config"] as const,
  secrets: () => [...agentQueryKeys.all, "secrets"] as const,
  users: () => [...agentQueryKeys.all, "users"] as const,
  aws: () => [...agentQueryKeys.all, "aws"] as const,
  apps: () => [...agentQueryKeys.all, "apps"] as const,
  appVariableLinks: () => [...agentQueryKeys.apps(), "links"] as const,
  variables: () => [...agentQueryKeys.all, "variables"] as const,

  // Services
  servicesStatus: () => [...agentQueryKeys.all, "servicesStatus"] as const,

  // SST Infrastructure
  sst: () => [...agentQueryKeys.all, "sst"] as const,
  sstStatus: () => [...agentQueryKeys.sst(), "status"] as const,
  sstConfig: () => [...agentQueryKeys.sst(), "config"] as const,
  sstOutputs: () => [...agentQueryKeys.sst(), "outputs"] as const,
  sstResources: () => [...agentQueryKeys.sst(), "resources"] as const,

  // Nixpkgs
  nixpkgs: () => [...agentQueryKeys.all, "nixpkgs"] as const,
  nixpkgsSearch: (query: string) =>
    [...agentQueryKeys.nixpkgs(), "search", query] as const,
  installedPackages: () => [...agentQueryKeys.nixpkgs(), "installed"] as const,

  // Process Compose
  processes: () => [...agentQueryKeys.all, "processes"] as const,

  // Healthchecks
  healthchecks: () => [...agentQueryKeys.all, "healthchecks"] as const,

  // Nix Config
  nixConfig: () => [...agentQueryKeys.all, "nixConfig"] as const,

  // Variables Backend
  variablesBackend: () => [...agentQueryKeys.all, "variablesBackend"] as const,

  // Recipients & Team Access
  recipients: () => [...agentQueryKeys.all, "recipients"] as const,
  rekeyWorkflow: () => [...agentQueryKeys.all, "rekeyWorkflow"] as const,
} as const;

/**
 * Query keys for shell status.
 */
export const shellQueryKeys = {
  status: () => [...agentQueryKeys.all, "shell", "status"] as const,
} as const;

// =============================================================================
// Real-time Query Sync via SSE
// =============================================================================

// =============================================================================
// Legacy Hooks (for backward compatibility)
// =============================================================================

interface UseAgentOptions {
  host?: string;
  port?: number;
  token?: string;
  /** Automatically connect when mounted (currently unused, for future use) */
  autoConnect?: boolean;
}

/**
 * React hook for interacting with the StackPanel agent.
 * Uses AgentHttpClient (HTTP).
 *
 * @deprecated Use the Connect-RPC based hooks (useApps, useVariables, etc.) instead.
 */
export function useAgent(options: UseAgentOptions = {}) {
  const { host = "localhost", port = 9876, token } = options;

  const client = useMemo(
    () => new AgentHttpClient({ host, port, token }),
    [host, port, token],
  );

  const { status } = useAgentHealth({ host, port });
  const isConnected = status === "available";

  return {
    isConnected,
    isConnecting: status === "checking",
    error: null as Error | null,
    connect: async () => {}, // No-op for HTTP
    disconnect: () => {}, // No-op for HTTP
    exec: (command: string, args?: string[]) => client.exec({ command, args }),
    nixEval: <T = unknown>(expression: string) =>
      client.nixEval(expression) as Promise<T>,
    nixGenerate: () => client.nixGenerate(),
    readFile: (path: string) => client.readFile(path),
    writeFile: (path: string, content: string) =>
      client.writeFile(path, content),
    setSecret: (env: "dev" | "staging" | "prod", key: string, value: string) =>
      client.setSecret({ env, key, value }),
  };
}

/**
 * Hook for checking if agent is available (health check)
 *
 * @deprecated Use the Connect-RPC based hooks instead.
 */
export function useAgentHealth(
  options: { host?: string; port?: number; intervalMs?: number } = {},
) {
  const { host = "localhost", port = 9876, intervalMs = 15e3 } = options;

  const [status, setStatus] = useState<
    "checking" | "available" | "unavailable"
  >("checking");
  const [projectRoot, setProjectRoot] = useState<string | null>(null);
  const [hasProject, setHasProject] = useState<boolean>(false);
  const [agentId, setAgentId] = useState<string | null>(null);

  useEffect(() => {
    const client = new AgentHttpClient(host, port);
    let isMounted = true;

    const check = () => {
      client.ping().then((data) => {
        if (!isMounted) return;
        if (data) {
          setStatus("available");
          setProjectRoot(data.projectRoot ?? null);
          setHasProject(data.hasProject ?? !!data.projectRoot);
          setAgentId((data as { agentId?: string }).agentId ?? null);
        } else {
          setStatus("unavailable");
          setProjectRoot(null);
          setHasProject(false);
          setAgentId(null);
        }
      });
    };

    check();
    const interval = setInterval(check, intervalMs);

    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, [host, port, intervalMs]);

  // isPaired = agent has a project loaded and is available
  const isPaired = status === "available" && hasProject;
  return { status, projectRoot, hasProject, agentId, isPaired };
}

// =============================================================================
// Client Hook
// =============================================================================

/**
 * Hook to get the Connect-RPC client for the agent.
 * Returns null if not connected.
 */
export function useAgentRpcClient() {
  const { host, port, token, isConnected } = useAgentContext();

  return useMemo(() => {
    if (!isConnected || !token) return null;
    const transport = createAgentTransport(token, host, port);
    return createClient(AgentService, transport);
  }, [host, isConnected, port, token]);
}

// =============================================================================
// Project
// =============================================================================

/**
 * Query hook for getting the current project info.
 */
export function useProject() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.project(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      const res = await client.getProject({});
      return res.project;
    },
    enabled: !!client,
  });
}

// =============================================================================
// Age Identity
// =============================================================================

/**
 * Query hook for getting the configured age identity.
 */
export function useAgeIdentity() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.ageIdentity(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getAgeIdentity({});
    },
    enabled: !!client,
  });
}

export function useSopsAgeKeysStatus() {
  const client = useAgentClient();

  return useQuery({
    queryKey: agentQueryKeys.sopsAgeKeysStatus(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getSopsAgeKeysStatus();
    },
    enabled: !!client,
  });
}

/**
 * Mutation hook for setting the age identity.
 */
export function useSetAgeIdentity() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (value: string) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setAgeIdentity({ value });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.ageIdentity() });
    },
  });
}

// =============================================================================
// KMS Config
// =============================================================================

/**
 * Query hook for getting the KMS configuration.
 */
export function useKMSConfig() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.kmsConfig(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getKMSConfig({});
    },
    enabled: !!client,
  });
}

/**
 * Mutation hook for setting the KMS configuration.
 */
export function useSetKMSConfig() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (config: {
      enable: boolean;
      keyArn: string;
      awsProfile?: string;
    }) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setKMSConfig(config);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.kmsConfig() });
    },
  });
}

// =============================================================================
// Entity Hooks (Apps, Variables, Users, Config, Secrets, AWS)
// =============================================================================

// For mutations, we accept the proto message type directly
// (proto-es messages are already properly typed)

/**
 * Fetch all apps from the agent.
 * Returns the apps map directly for compatibility with existing components.
 */
export function useApps() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.apps(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      const response = await client.getApps({});
      // Return the apps map directly for compatibility
      return response.apps ?? {};
    },
    enabled: !!client,
  });
}

/**
 * Mutation to update apps.
 */
export function useSetApps() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (
      apps: Parameters<NonNullable<typeof client>["setApps"]>[0],
    ) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setApps(apps);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.apps() });
    },
  });
}

/**
 * Fetch raw app env -> variable link metadata from config.nix source.
 */
export function useAppVariableLinks() {
  const client = useAgentClient();

  return useQuery({
    queryKey: agentQueryKeys.appVariableLinks(),
    queryFn: async (): Promise<AppVariableLinks> => {
      return client.getAppVariableLinks();
    },
  });
}

/**
 * Fetch all variables from the agent.
 * Returns the variables map directly for compatibility with existing components.
 */
export function useVariables() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  useAgentSSEEvent("config.changed", () => {
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
  });

  useAgentSSEEvent("flake.config.updated", () => {
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
  });

  useAgentSSEEvent("config.refreshed", () => {
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
  });

  return useQuery({
    queryKey: agentQueryKeys.variables(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      const response = await client.getVariables({});
      // Return the variables map directly for compatibility
      return response.variables ?? {};
    },
    enabled: !!client,
  });
}

/**
 * Mutation to update variables.
 */
export function useSetVariables() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (
      variables: Parameters<NonNullable<typeof client>["setVariables"]>[0],
    ) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setVariables(variables);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
    },
  });
}

/**
 * Fetch all users from the agent.
 */
export function useUsers() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.users(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getUsers({});
    },
    enabled: !!client,
  });
}

/**
 * Mutation to update users.
 */
export function useSetUsers() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (
      users: Parameters<NonNullable<typeof client>["setUsers"]>[0],
    ) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setUsers(users);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.users() });
    },
  });
}

/**
 * Fetch the config from the agent.
 */
export function useConfig() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.config(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getConfig({});
    },
    enabled: !!client,
  });
}

/**
 * Mutation to update config.
 */
export function useSetConfig() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (
      config: Parameters<NonNullable<typeof client>["setConfig"]>[0],
    ) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setConfig(config);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.config() });
    },
  });
}

/**
 * Fetch all secrets from the agent.
 */
export function useSecrets() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.secrets(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getSecrets({});
    },
    enabled: !!client,
  });
}

/**
 * Mutation to update secrets.
 */
export function useSetSecrets() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (
      secrets: Parameters<NonNullable<typeof client>["setSecrets"]>[0],
    ) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setSecrets(secrets);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.secrets() });
    },
  });
}

/**
 * Fetch AWS config from the agent.
 */
export function useAws() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.aws(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getAws({});
    },
    enabled: !!client,
  });
}

/**
 * Mutation to update AWS config.
 */
export function useSetAws() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (
      aws: Parameters<NonNullable<typeof client>["setAws"]>[0],
    ) => {
      if (!client) throw new Error("Not connected to agent");
      return client.setAws(aws);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.aws() });
    },
  });
}

// =============================================================================
// Services Status
// =============================================================================

/**
 * Query hook for getting the services status.
 */
export function useServicesStatus() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.servicesStatus(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getServicesStatus({});
    },
    enabled: !!client,
    refetchInterval: 5000, // Refresh every 5 seconds
  });
}

// =============================================================================
// Nix Operations
// =============================================================================

/**
 * Mutation hook for running nix generate.
 */
export function useNixGenerate() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.nixGenerate({});
    },
    onSuccess: () => {
      // Invalidate all agent queries after generation
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.all });
    },
  });
}

/**
 * Mutation hook for running nix eval.
 */
export function useNixEval() {
  const client = useAgentRpcClient();

  return useMutation({
    mutationFn: async (args: { expression: string; json?: boolean }) => {
      if (!client) throw new Error("Not connected to agent");
      return client.nixEval(args);
    },
  });
}

// =============================================================================
// Command Execution
// =============================================================================

/**
 * Mutation hook for executing commands.
 */
export function useExec() {
  const client = useAgentRpcClient();

  return useMutation({
    mutationFn: async (args: {
      command: string;
      args?: string[];
      cwd?: string;
      env?: Record<string, string>;
    }) => {
      if (!client) throw new Error("Not connected to agent");
      return client.exec(args);
    },
  });
}

// =============================================================================
// SST Infrastructure
// =============================================================================

/**
 * Query hook for getting the SST deployment status.
 */
export function useSSTStatus() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.sstStatus(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getSSTStatus({});
    },
    enabled: !!client,
  });
}

/**
 * Query hook for getting the SST configuration.
 */
export function useSSTConfig() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.sstConfig(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getSSTConfig({});
    },
    enabled: !!client,
  });
}

/**
 * Query hook for getting the SST outputs.
 */
export function useSSTOutputs() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.sstOutputs(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getSSTOutputs({});
    },
    enabled: !!client,
  });
}

/**
 * Query hook for getting the SST resources.
 */
export function useSSTResources() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.sstResources(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getSSTResources({});
    },
    enabled: !!client,
  });
}

/**
 * Mutation hook for deploying SST infrastructure.
 */
export function useDeploySST() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (stage: string = "dev") => {
      if (!client) throw new Error("Not connected to agent");
      return client.deploySST({ stage });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.sst() });
    },
  });
}

/**
 * Mutation hook for removing SST infrastructure.
 */
export function useRemoveSST() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (stage: string = "dev") => {
      if (!client) throw new Error("Not connected to agent");
      return client.removeSST({ stage });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.sst() });
    },
  });
}

// =============================================================================
// Nixpkgs Package Management
// =============================================================================

/**
 * Query hook for searching nixpkgs packages.
 */
export function useSearchNixpkgs(
  query: string,
  options?: { enabled?: boolean },
) {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.nixpkgsSearch(query),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.searchNixpkgs({ query, limit: 20 });
    },
    enabled: !!client && !!query && (options?.enabled ?? true),
  });
}

/**
 * Query hook for getting installed packages.
 */
export function useInstalledPackages() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.installedPackages(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getInstalledPackages({});
    },
    enabled: !!client,
  });
}

// =============================================================================
// Process Compose
// =============================================================================

/**
 * Query hook for getting process-compose processes.
 */
export function useProcesses() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.processes(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getProcesses({});
    },
    enabled: !!client,
    refetchInterval: 5000, // Refresh every 5 seconds
  });
}

/**
 * Query hook for getting process-compose project state.
 * Includes process counts, memory stats, and version info.
 */
export function useProcessComposeProjectState() {
  const client = useAgentClient();
  const { isConnected } = useAgentContext();

  return useQuery({
    queryKey: [...agentQueryKeys.processes(), "projectState"],
    queryFn: async () => {
      return client.getProcessComposeProjectState();
    },
    enabled: isConnected,
    refetchInterval: 5000,
  });
}

/**
 * Query hook for getting logs for a specific process.
 */
export function useProcessLogs(
  name: string,
  options?: { offset?: number; limit?: number; enabled?: boolean },
) {
  const client = useAgentClient();
  const { isConnected } = useAgentContext();
  const { offset = 0, limit = 100, enabled = true } = options ?? {};

  return useQuery({
    queryKey: [...agentQueryKeys.processes(), "logs", name, offset, limit],
    queryFn: async () => {
      return client.getProcessLogs(name, offset, limit);
    },
    enabled: isConnected && enabled && !!name,
    refetchInterval: 2000, // Refresh logs every 2 seconds
  });
}

/**
 * Query hook for getting ports used by a specific process.
 */
export function useProcessPorts(name: string, options?: { enabled?: boolean }) {
  const client = useAgentClient();
  const { isConnected } = useAgentContext();

  return useQuery({
    queryKey: [...agentQueryKeys.processes(), "ports", name],
    queryFn: async () => {
      return client.getProcessPorts(name);
    },
    enabled: isConnected && (options?.enabled ?? true) && !!name,
  });
}

/**
 * Mutation hook for starting a process.
 */
export function useStartProcess() {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (name: string) => {
      return client.startProcess(name);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.processes() });
    },
  });
}

/**
 * Mutation hook for stopping a process.
 */
export function useStopProcess() {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (name: string) => {
      return client.stopProcess(name);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.processes() });
    },
  });
}

/**
 * Mutation hook for restarting a process.
 */
export function useRestartProcess() {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (name: string) => {
      return client.restartProcess(name);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.processes() });
    },
  });
}

// =============================================================================
// Healthchecks
// =============================================================================

/**
 * Query hook for getting healthcheck status.
 */
export function useHealthchecks() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.healthchecks(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getHealthchecks({});
    },
    enabled: !!client,
  });
}

// =============================================================================
// Full Nix Config
// =============================================================================

/**
 * Query hook for getting the full Nix configuration.
 */
export function useNixConfigQuery(options?: { refresh?: boolean }) {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: agentQueryKeys.nixConfig(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      const response = await client.getNixConfig({
        refresh: options?.refresh ?? false,
      });
      // Parse the JSON config
      if (response.configJson) {
        return {
          ...response,
          config: JSON.parse(response.configJson) as Record<string, unknown>,
        };
      }
      return { ...response, config: null };
    },
    enabled: !!client,
  });
}

/**
 * Mutation hook for forcing a Nix config refresh.
 */
export function useRefreshNixConfig() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      const response = await client.refreshNixConfig({});
      // Parse the JSON config
      if (response.configJson) {
        return {
          ...response,
          config: JSON.parse(response.configJson) as Record<string, unknown>,
        };
      }
      return { ...response, config: null };
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() });
      // Also invalidate all agent queries since config affects everything
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.all });
    },
  });
}

// =============================================================================
// Variables Backend
// =============================================================================

/** Response shape from /api/secrets/backend */
export interface VariablesBackendResponse {
  backend: "vals" | "chamber";
  chamber?: { servicePrefix: string };
}

/**
 * Query hook for getting the variables backend configuration.
 * Returns whether the project uses "vals" (AGE/SOPS) or "chamber" (AWS SSM).
 *
 * Uses the HTTP client since there is no proto definition for this endpoint yet.
 */
export function useVariablesBackend() {
  const client = useAgentClient();
  const { isConnected } = useAgentContext();

  return useQuery({
    queryKey: agentQueryKeys.variablesBackend(),
    queryFn: async (): Promise<VariablesBackendResponse> => {
      return client.getVariablesBackend();
    },
    enabled: isConnected,
    staleTime: 60_000, // backend doesn't change at runtime
  });
}

/**
 * Convenience helper: returns true when the backend is "chamber".
 */
export function useIsChamberBackend(): boolean {
  const { data } = useVariablesBackend();
  return data?.backend === "chamber";
}

// =============================================================================
// Recipients
// =============================================================================

/**
 * Fetch the list of AGE recipients (public keys registered for secrets access).
 */
export function useRecipients() {
  const client = useAgentClient();
  const { isConnected } = useAgentContext();

  return useQuery<RecipientListResponse>({
    queryKey: agentQueryKeys.recipients(),
    queryFn: async () => {
      if (!client) throw new Error("No agent client");
      return client.listRecipients();
    },
    enabled: isConnected,
    staleTime: 30_000,
  });
}

/**
 * Mutation to add a new recipient.
 */
export function useAddRecipient() {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (request: {
      name: string;
      publicKey?: string;
      sshPublicKey?: string;
      tags?: string[];
    }) => {
      if (!client) throw new Error("No agent client");
      return client.addRecipient(request);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: agentQueryKeys.recipients(),
      });
      queryClient.invalidateQueries({
        queryKey: agentQueryKeys.nixConfig(),
      });
    },
  });
}

/**
 * Mutation to remove a recipient.
 */
export function useRemoveRecipient() {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (name: string) => {
      if (!client) throw new Error("No agent client");
      return client.removeRecipient(name);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: agentQueryKeys.recipients(),
      });
      queryClient.invalidateQueries({
        queryKey: agentQueryKeys.nixConfig(),
      });
    },
  });
}

// =============================================================================
// Rekey Workflow
// =============================================================================

/**
 * Fetch the status of the GitHub Actions secrets rekey workflow.
 */
export function useRekeyWorkflowStatus() {
  const client = useAgentClient();
  const { isConnected } = useAgentContext();

  return useQuery<RekeyWorkflowStatus>({
    queryKey: agentQueryKeys.rekeyWorkflow(),
    queryFn: async () => {
      if (!client) throw new Error("No agent client");
      return client.getRekeyWorkflowStatus();
    },
    enabled: isConnected,
    staleTime: 60_000,
  });
}

// =============================================================================
// Secrets Verification
// =============================================================================

/**
 * Mutation to verify encrypt/decrypt round-trip for a secrets group.
 */
export function useVerifySecrets() {
  const client = useAgentClient();

  return useMutation({
    mutationFn: async (group: string) => {
      if (!client) throw new Error("No agent client");
      return client.verifySecrets(group);
    },
  });
}

// =============================================================================
// Compatibility Layer (for gradual migration from use-nix-config.ts)
// =============================================================================

/**
 * Compatibility wrapper for useNixConfig - matches the old API signature.
 *
 * @deprecated Use useNixConfigQuery() for new code.
 */
export function useNixConfig(_options?: { autoRefetch?: boolean }) {
  const query = useNixConfigQuery({ refresh: false });
  const refreshMutation = useRefreshNixConfig();

  return {
    data: query.data?.config ?? null,
    error: query.error,
    isLoading: query.isLoading,
    isError: query.isError,
    isSuccess: query.isSuccess,
    refetch: query.refetch,
    forceRefresh: refreshMutation.mutateAsync,
    isRefreshing: refreshMutation.isPending,
  };
}

// =============================================================================
// Compatibility Layer - Generic Entity Hooks
// =============================================================================

// Re-export kebab/snake case utilities for entity data transformation
import { kebabToSnake, snakeToKebab } from "./nix-data";

/**
 * Generic hook for accessing Nix data entities (single objects).
 * Uses the legacy HTTP client under the hood.
 *
 * @deprecated For standard entities, prefer specific hooks:
 * - apps → useApps()
 * - variables → useVariables()
 * - users → useUsers()
 * - config → useConfig()
 * - secrets → useSecrets()
 * - aws → useAws()
 */
export function useNixData<T>(
  entity: string,
  options: { initialData?: T; autoRefetch?: boolean } = {},
) {
  const { initialData, autoRefetch = true } = options;
  const client = useAgentClient();
  const queryClient = useQueryClient();

  const queryKey = [...agentQueryKeys.all, "entity", entity];

  const query = useQuery({
    queryKey,
    queryFn: async () => {
      // Use the underlying HTTP API to fetch entity data
      const response = await client.get<{
        success: boolean;
        data: { entity: string; exists: boolean; data: T };
      }>(`/api/nix/data?entity=${encodeURIComponent(entity)}`);

      if (!response.success || !response.data.exists) {
        return null;
      }
      return kebabToSnake(response.data.data) as T;
    },
    initialData,
    refetchOnWindowFocus: autoRefetch,
  });

  const mutation = useMutation({
    mutationFn: async (data: T) => {
      await client.post("/api/nix/data", {
        entity,
        data: snakeToKebab(data),
      });
      // Return the new data
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey });
    },
  });

  return {
    ...query,
    mutate: mutation.mutateAsync,
    refetch: query.refetch,
  };
}

/**
 * Generic hook for map-style Nix data entities with key-level operations.
 * Uses the legacy HTTP client under the hood.
 *
 * @deprecated For standard entities, prefer specific hooks:
 * - apps → useApps() + useSetApps()
 * - variables → useVariables() + useSetVariables()
 */
export function useNixMapData<V>(
  entity: string,
  options: { initialData?: Record<string, V>; autoRefetch?: boolean } = {},
) {
  const { initialData, autoRefetch = true } = options;
  const client = useAgentClient();
  const queryClient = useQueryClient();
  const mapClient = useMemo(
    () => client.mapEntity<V>(entity),
    [client, entity],
  );

  const queryKey = [...agentQueryKeys.all, "mapEntity", entity];

  const query = useQuery({
    queryKey,
    queryFn: async () => {
      return mapClient.all();
    },
    initialData,
    refetchOnWindowFocus: autoRefetch,
  });

  const setMutation = useMutation({
    mutationFn: async ({ key, value }: { key: string; value: V }) => {
      await mapClient.set(key, value);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey });
    },
  });

  const updateMutation = useMutation({
    mutationFn: async ({
      key,
      updates,
    }: {
      key: string;
      updates: Partial<V>;
    }) => {
      await mapClient.update(key, updates);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey });
    },
  });

  const removeMutation = useMutation({
    mutationFn: async (key: string) => {
      await mapClient.remove(key);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey });
    },
  });

  return {
    ...query,
    set: (key: string, value: V) => setMutation.mutateAsync({ key, value }),
    update: (key: string, updates: Partial<V>) =>
      updateMutation.mutateAsync({ key, updates }),
    remove: (key: string) => removeMutation.mutateAsync(key),
    refetch: query.refetch,
  };
}

export function useNixEntityData<T>(
  entity: string,
  options: { initialData?: T | null; autoRefetch?: boolean } = {},
) {
  const { initialData, autoRefetch = true } = options;
  const client = useAgentClient();
  const queryClient = useQueryClient();
  const entityClient = useMemo(
    () => client.entity<T>(entity),
    [client, entity],
  );

  const queryKey = [...agentQueryKeys.all, "entity", entity];

  const query = useQuery({
    queryKey,
    queryFn: async () => entityClient.get(),
    initialData,
    refetchOnWindowFocus: autoRefetch,
  });

  const setMutation = useMutation({
    mutationFn: async (data: T) => entityClient.set(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey });
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() });
    },
  });

  const updateMutation = useMutation({
    mutationFn: async (updates: Partial<T>) => entityClient.update(updates),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey });
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() });
    },
  });

  return {
    ...query,
    set: (data: T) => setMutation.mutateAsync(data),
    update: (updates: Partial<T>) => updateMutation.mutateAsync(updates),
    refetch: query.refetch,
  };
}

// =============================================================================
// Turbo Package Graph
// =============================================================================

export interface TurboTask {
  name: string;
  command?: string;
}

export interface TurboPackage {
  name: string;
  path: string;
  tasks: TurboTask[];
}

/**
 * Hook for fetching the turbo package graph with tasks.
 * This is the source of truth for available tasks in the monorepo.
 */
export function useTurboPackages() {
  const client = useAgentClient();

  const query = useQuery({
    queryKey: [...agentQueryKeys.all, "turboPackages"],
    queryFn: async () => {
      const packages = await client.getPackageGraph({ excludeRoot: true });
      return packages as TurboPackage[];
    },
  });

  const allTasks = useMemo(() => {
    const taskSet = new Set<string>();
    for (const pkg of query.data ?? []) {
      for (const task of pkg.tasks) {
        taskSet.add(task.name);
      }
    }
    return Array.from(taskSet).sort();
  }, [query.data]);

  const tasksMap = useMemo((): Record<string, { name: string }> => {
    const map: Record<string, { name: string }> = {};
    for (const taskName of allTasks) {
      map[taskName] = { name: taskName };
    }
    return map;
  }, [allTasks]);

  const getTasksForPackage = (packageName: string): Array<{ name: string }> => {
    const pkg = (query.data ?? []).find((p) => p.name === packageName);
    if (!pkg) return [];
    return pkg.tasks.map((t) => ({ name: t.name }));
  };

  return {
    packages: query.data ?? [],
    allTasks,
    tasksMap,
    getTasksForPackage,
    isLoading: query.isLoading,
    isError: query.isError,
    isSuccess: query.isSuccess,
    error: query.error,
    refetch: query.refetch,
  };
}

/**
 * Hook for accessing turbo tasks from the package graph.
 * This is a convenience wrapper around useTurboPackages that returns just the tasks.
 */
export function useTurboTasks() {
  const { tasksMap, isLoading, isError, isSuccess, error, refetch } =
    useTurboPackages();

  return {
    data: tasksMap,
    isLoading,
    isError,
    isSuccess,
    error,
    refetch,
  };
}

// =============================================================================
// Derived Hooks
// =============================================================================

/**
 * Hook to find which apps have a specific variable (by env key name).
 * Searches across all environments in each app.
 */
export function useAppsWithVariable(variableName: string) {
  const { data: apps, isLoading, error, refetch } = useApps();

  const matchingApps = useMemo(() => {
    if (!apps) return null;

    return Object.entries(apps)
      .filter(([_, app]) => {
        return flattenConfiguredAppVariables(app).some(
          (mapping) => mapping.envKey === variableName,
        );
      })
      .map(([id, app]) => ({ ...app, id }));
  }, [apps, variableName]);

  return {
    data: matchingApps,
    isLoading,
    isError: !!error,
    isSuccess: !!matchingApps,
    error,
    refetch,
  };
}

/**
 * Hook to get a single app by ID.
 */
export function useApp(appId: string) {
  const { data: apps, isLoading, isError, error, refetch } = useApps();

  const app = useMemo(() => {
    if (!apps) return null;
    return apps[appId] ?? null;
  }, [apps, appId]);

  return {
    data: app,
    isLoading,
    isError,
    isSuccess: !!app,
    error,
    refetch,
  };
}

/**
 * Hook for workspace-level task definitions.
 */
export function useTasks() {
  return useNixMapData<{ exec: string; description?: string; cwd?: string }>(
    "tasks",
  );
}

/**
 * Hook for managing services configuration.
 */
export function useServices() {
  return useNixMapData<{ enable?: boolean; port?: number }>("services");
}

// =============================================================================
// Shell Status (Devshell Management)
// =============================================================================

/**
 * Query hook for getting the devshell status.
 * Returns whether the shell is stale (nix files changed since last rebuild).
 */
export function useShellStatus() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: shellQueryKeys.status(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getShellStatus({});
    },
    enabled: !!client,
    refetchInterval: 10000, // Poll every 10 seconds as backup
  });
}

/**
 * Mutation hook for rebuilding the devshell.
 * Returns an async iterator that streams rebuild events.
 */
export function useRebuildShell() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();
  const [isRebuilding, setIsRebuilding] = useState(false);
  const [output, setOutput] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);

  const rebuild = async (method: "devshell" | "nix" = "devshell") => {
    if (!client) throw new Error("Not connected to agent");

    setIsRebuilding(true);
    setOutput([]);
    setError(null);

    try {
      const stream = client.rebuildShell({ method });

      for await (const event of stream) {
        switch (event.type) {
          case "started":
            // Rebuild started
            break;
          case "output":
            if (event.output) {
              setOutput((prev) => [...prev, event.output]);
            }
            break;
          case "completed":
            // Invalidate shell status after successful rebuild
            if (event.exitCode === 0) {
              queryClient.invalidateQueries({
                queryKey: shellQueryKeys.status(),
              });
            }
            setIsRebuilding(false);
            return { success: event.exitCode === 0, exitCode: event.exitCode };
          case "error":
            setError(event.error || "Unknown error");
            setIsRebuilding(false);
            return { success: false, error: event.error };
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to rebuild shell");
      setIsRebuilding(false);
      throw err;
    }

    setIsRebuilding(false);
    return { success: false };
  };

  return {
    rebuild,
    isRebuilding,
    output,
    error,
    clearOutput: () => setOutput([]),
    clearError: () => setError(null),
  };
}

// =============================================================================
// Modules (Connect-RPC)
// =============================================================================

export const moduleRpcQueryKeys = {
  all: ["modules-rpc"] as const,
  list: () => [...moduleRpcQueryKeys.all, "list"] as const,
  detail: (id: string) => [...moduleRpcQueryKeys.all, "detail", id] as const,
};

/**
 * Query hook for getting all modules via Connect-RPC.
 */
export function useModulesRpc() {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: moduleRpcQueryKeys.list(),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      const res = await client.getModules({});
      return res.modules ?? {};
    },
    enabled: !!client,
    staleTime: 30 * 1000,
  });
}

/**
 * Query hook for getting a single module by ID via Connect-RPC.
 */
export function useModuleRpc(moduleId: string) {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: moduleRpcQueryKeys.detail(moduleId),
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getModule({ moduleId });
    },
    enabled: !!client && !!moduleId,
    staleTime: 30 * 1000,
  });
}

/**
 * Mutation hook for enabling a module via Connect-RPC.
 */
export function useEnableModuleRpc() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      moduleId,
      settings,
    }: {
      moduleId: string;
      settings?: Record<string, string>;
    }) => {
      if (!client) throw new Error("Not connected to agent");
      return client.enableModule({ moduleId, settings: settings ?? {} });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: moduleRpcQueryKeys.all });
    },
  });
}

/**
 * Mutation hook for disabling a module via Connect-RPC.
 */
export function useDisableModuleRpc() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (moduleId: string) => {
      if (!client) throw new Error("Not connected to agent");
      return client.disableModule({ moduleId });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: moduleRpcQueryKeys.all });
    },
  });
}

/**
 * Mutation hook for updating module settings via Connect-RPC.
 */
export function useUpdateModuleSettingsRpc() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      moduleId,
      settings,
    }: {
      moduleId: string;
      settings: Record<string, string>;
    }) => {
      if (!client) throw new Error("Not connected to agent");
      return client.updateModuleSettings({ moduleId, settings });
    },
    onSuccess: (_data, { moduleId }) => {
      queryClient.invalidateQueries({ queryKey: moduleRpcQueryKeys.all });
      queryClient.invalidateQueries({
        queryKey: moduleRpcQueryKeys.detail(moduleId),
      });
    },
  });
}

/**
 * Query hook for getting module outputs (files, scripts, healthchecks, packages).
 */
export function useModuleOutputsRpc(moduleId: string) {
  const client = useAgentRpcClient();

  return useQuery({
    queryKey: [...moduleRpcQueryKeys.detail(moduleId), "outputs"],
    queryFn: async () => {
      if (!client) throw new Error("Not connected to agent");
      return client.getModuleOutputs({ moduleId });
    },
    enabled: !!client && !!moduleId,
    staleTime: 60 * 1000, // 1 minute - outputs don't change often
  });
}

/**
 * Re-export proto types for convenience.
 */
export type { Apps, Variables, Users, Config, Secrets, Aws };

// Re-export module proto types
export type {
  Module,
  Modules,
  ModuleMeta,
  ModuleSource,
  ModuleFeatures,
  ModulePanel,
  ModulePanelField,
  ModuleAppData,
  ModuleCategory,
  ModuleSourceType,
  ModulePanelType,
  ModuleFieldType,
  EnableModuleRequest,
  DisableModuleRequest,
  UpdateModuleSettingsRequest,
  ModuleResponse,
  ModuleOutputs,
  ModuleOutputFile,
  ModuleOutputScript,
  ModuleOutputHealthcheck,
  ModuleOutputPackage,
  GetModuleOutputsRequest,
} from "@stackpanel/proto";

// =============================================================================
// PatchNixData - Partial updates to Nix data entities
// =============================================================================

/**
 * Parameters for patching a single value in a Nix data entity.
 */
export interface PatchNixDataParams {
  /** Entity name (e.g., "apps", "config") */
  entity: string;
  /** Top-level key within the entity (e.g., app name "web"). Empty for non-map entities. */
  key: string;
  /** Dot-separated camelCase path to the field (e.g., "go.mainPackage") */
  path: string;
  /** JSON-encoded value (e.g., '"./cmd/api"', "true", '["a","b"]') */
  value: string;
  /** Value type hint: "string" | "bool" | "number" | "list" | "object" | "null" */
  valueType: string;
}

/**
 * Mutation hook for patching a single value within a Nix data entity.
 *
 * This enables editing individual fields from UI panels (e.g., app config forms)
 * without replacing the entire entity.
 *
 * @example
 * ```tsx
 * const patchNixData = usePatchNixData();
 *
 * patchNixData.mutate({
 *   entity: "apps",
 *   key: "web",
 *   path: "go.mainPackage",
 *   value: JSON.stringify("./cmd/api"),
 *   valueType: "string",
 * });
 * ```
 */
export function usePatchNixData() {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: PatchNixDataParams) => {
      if (!client) throw new Error("Not connected to agent");
      const response = await client.patchNixData({
        entity: params.entity,
        key: params.key,
        path: params.path,
        value: params.value,
        valueType: params.valueType,
      });
      if (!response.success) {
        throw new Error(response.error || "PatchNixData failed");
      }
      return response;
    },
    onSuccess: (_data, params) => {
      // Invalidate the entity-specific query cache
      const entityKey = params.entity as keyof typeof agentQueryKeys;
      if (entityKey in agentQueryKeys) {
        const keyFn = agentQueryKeys[entityKey];
        if (typeof keyFn === "function") {
          queryClient.invalidateQueries({
            queryKey: (keyFn as () => readonly string[])(),
          });
        }
      }
      if (params.entity === "apps") {
        queryClient.invalidateQueries({
          queryKey: agentQueryKeys.appVariableLinks(),
        });
      }
      // Also invalidate the full nix config (it includes panel data)
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() });
    },
  });
}

// =============================================================================
// Real-time Query Sync via SSE
// =============================================================================

/**
 * Hook to set up SSE listeners that automatically invalidate React Query caches
 * when the agent broadcasts configuration or state changes.
 *
 * This should be mounted at a high level (e.g., in the root StudioLayout) so that
 * all queries stay in sync with server-side changes in real-time.
 */
export function useAgentLiveQuerySync() {
  const queryClient = useQueryClient();

  // Invalidate config/variables when they change on the server
  useAgentSSEEvent("config.changed", () => {
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() });
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.all });
  });

  useAgentSSEEvent("flake.config.updated", () => {
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() });
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.all });
  });

  useAgentSSEEvent("config.refreshed", () => {
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() });
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.all });
  });

  // Invalidate turbo package graph when dependencies change
  useAgentSSEEvent("turbo.changed", () => {
    queryClient.invalidateQueries({
      queryKey: [...agentQueryKeys.all, "turboPackages"],
    });
  });

  // Invalidate processes when they change
  useAgentSSEEvent("process.changed", () => {
    queryClient.invalidateQueries({ queryKey: agentQueryKeys.processes() });
  });

  // Invalidate shell status when it changes
  useAgentSSEEvent("shell.stale", () => {
    queryClient.invalidateQueries({ queryKey: shellQueryKeys.status() });
  });

  useAgentSSEEvent("shell.rebuilt", () => {
    queryClient.invalidateQueries({ queryKey: shellQueryKeys.status() });
  });
}
