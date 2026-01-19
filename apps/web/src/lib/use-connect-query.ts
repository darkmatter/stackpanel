/**
 * TanStack Query hooks for Connect-RPC agent APIs.
 *
 * Provides React Query integration with automatic caching, refetching, etc.
 * Types are fully generated from proto definitions.
 */

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useConnectClient } from "./use-connect-client";

// Entity types - these are the proto-generated types
// Using the protobuf-ts generated types for better TypeScript ergonomics
import type { Apps, Variables, Users, Config, Secrets, Aws } from "@stackpanel/proto";

// For mutations, we accept partial objects and cast to MessageInit
// This is a workaround for the two different proto type systems (protobuf-ts vs bufbuild)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type MessageInit<T> = T extends object ? Partial<T> | any : T;

// =============================================================================
// Query Keys
// =============================================================================

export const agentQueryKeys = {
  all: ["agent"] as const,
  apps: () => [...agentQueryKeys.all, "apps"] as const,
  variables: () => [...agentQueryKeys.all, "variables"] as const,
  users: () => [...agentQueryKeys.all, "users"] as const,
  config: () => [...agentQueryKeys.all, "config"] as const,
  secrets: () => [...agentQueryKeys.all, "secrets"] as const,
  aws: () => [...agentQueryKeys.all, "aws"] as const,
  project: () => [...agentQueryKeys.all, "project"] as const,
} as const;

// =============================================================================
// Apps Hooks
// =============================================================================

/**
 * Fetch all apps from the agent.
 */
export function useApps() {
  const client = useConnectClient();

  return useQuery({
    queryKey: agentQueryKeys.apps(),
    queryFn: async () => {
      const response = await client.getApps({});
      return response;
    },
  });
}

/**
 * Mutation to update apps.
 */
export function useSetApps() {
  const client = useConnectClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (apps: MessageInit<Apps>) => {
      const response = await client.setApps(apps);
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.apps() });
    },
  });
}

// =============================================================================
// Variables Hooks
// =============================================================================

/**
 * Fetch all variables from the agent.
 */
export function useVariables() {
  const client = useConnectClient();

  return useQuery({
    queryKey: agentQueryKeys.variables(),
    queryFn: async () => {
      const response = await client.getVariables({});
      return response;
    },
  });
}

/**
 * Mutation to update variables.
 */
export function useSetVariables() {
  const client = useConnectClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (variables: MessageInit<Variables>) => {
      const response = await client.setVariables(variables);
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.variables() });
    },
  });
}

// =============================================================================
// Users Hooks
// =============================================================================

/**
 * Fetch all users from the agent.
 */
export function useUsers() {
  const client = useConnectClient();

  return useQuery({
    queryKey: agentQueryKeys.users(),
    queryFn: async () => {
      const response = await client.getUsers({});
      return response;
    },
  });
}

/**
 * Mutation to update users.
 */
export function useSetUsers() {
  const client = useConnectClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (users: MessageInit<Users>) => {
      const response = await client.setUsers(users);
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.users() });
    },
  });
}

// =============================================================================
// Config Hooks
// =============================================================================

/**
 * Fetch the config from the agent.
 */
export function useConfig() {
  const client = useConnectClient();

  return useQuery({
    queryKey: agentQueryKeys.config(),
    queryFn: async () => {
      const response = await client.getConfig({});
      return response;
    },
  });
}

/**
 * Mutation to update config.
 */
export function useSetConfig() {
  const client = useConnectClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (config: MessageInit<Config>) => {
      const response = await client.setConfig(config);
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.config() });
    },
  });
}

// =============================================================================
// Secrets Hooks
// =============================================================================

/**
 * Fetch all secrets from the agent.
 */
export function useSecrets() {
  const client = useConnectClient();

  return useQuery({
    queryKey: agentQueryKeys.secrets(),
    queryFn: async () => {
      const response = await client.getSecrets({});
      return response;
    },
  });
}

/**
 * Mutation to update secrets.
 */
export function useSetSecrets() {
  const client = useConnectClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (secrets: MessageInit<Secrets>) => {
      const response = await client.setSecrets(secrets);
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.secrets() });
    },
  });
}

// =============================================================================
// AWS Hooks
// =============================================================================

/**
 * Fetch AWS config from the agent.
 */
export function useAws() {
  const client = useConnectClient();

  return useQuery({
    queryKey: agentQueryKeys.aws(),
    queryFn: async () => {
      const response = await client.getAws({});
      return response;
    },
  });
}

/**
 * Mutation to update AWS config.
 */
export function useSetAws() {
  const client = useConnectClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (aws: MessageInit<Aws>) => {
      const response = await client.setAws(aws);
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: agentQueryKeys.aws() });
    },
  });
}

// =============================================================================
// Project Hooks
// =============================================================================

/**
 * Fetch the current project from the agent.
 */
export function useProject() {
  const client = useConnectClient();

  return useQuery({
    queryKey: agentQueryKeys.project(),
    queryFn: async () => {
      const response = await client.getProject({});
      return response.project;
    },
  });
}
