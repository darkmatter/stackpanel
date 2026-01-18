/**
 * React hooks for type-safe RPC communication with the Stackpanel agent.
 *
 * These hooks wrap the proto-generated Connect-RPC service and provide
 * a convenient API for React components.
 */

import { createClient } from "@connectrpc/connect";
import { AgentService } from "@stackpanel/proto/agent";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import { useAgentContext } from "./agent-provider";
import { createAgentTransport } from "./connect-transport";

// Query keys for cache management
export const agentQueryKeys = {
	project: ["agent", "project"] as const,
	ageIdentity: ["agent", "ageIdentity"] as const,
	kmsConfig: ["agent", "kmsConfig"] as const,
	config: ["agent", "config"] as const,
	secrets: ["agent", "secrets"] as const,
	users: ["agent", "users"] as const,
	aws: ["agent", "aws"] as const,
	apps: ["agent", "apps"] as const,
	variables: ["agent", "variables"] as const,
	servicesStatus: ["agent", "servicesStatus"] as const,
};

/**
 * Hook to get the Connect-RPC client for the agent.
 * Returns null if not connected.
 */
export function useAgentRpcClient() {
	const { token, isConnected } = useAgentContext();

	return useMemo(() => {
		if (!isConnected || !token) return null;
		const transport = createAgentTransport(token);
		return createClient(AgentService, transport);
	}, [token, isConnected]);
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
		queryKey: agentQueryKeys.project,
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
		queryKey: agentQueryKeys.ageIdentity,
		queryFn: async () => {
			if (!client) throw new Error("Not connected to agent");
			return client.getAgeIdentity({});
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
			queryClient.invalidateQueries({ queryKey: agentQueryKeys.ageIdentity });
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
		queryKey: agentQueryKeys.kmsConfig,
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
			queryClient.invalidateQueries({ queryKey: agentQueryKeys.kmsConfig });
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
		queryKey: agentQueryKeys.servicesStatus,
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

	return useMutation({
		mutationFn: async () => {
			if (!client) throw new Error("Not connected to agent");
			return client.nixGenerate({});
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
