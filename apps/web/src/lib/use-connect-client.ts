/**
 * Connect-RPC client hooks for the Stackpanel agent.
 *
 * Provides type-safe access to agent APIs using the generated Connect client.
 * Uses proto-generated types - no manual type definitions needed.
 */

import { useMemo } from "react";
import { createConnectTransport } from "@connectrpc/connect-web";
import { createClient, type Transport } from "@connectrpc/connect";
import { AgentService } from "@stackpanel/agent-client";
import { useAgentContext } from "./agent-provider";

/**
 * Create a Connect transport for the agent.
 */
export function createAgentTransport(
  host: string,
  port: number,
  token?: string,
): Transport {
  const baseUrl = `http://${host}:${port}`;

  return createConnectTransport({
    baseUrl,
    useBinaryFormat: false, // Use JSON for easier debugging
    interceptors: token
      ? [
          (next) => async (req) => {
            req.header.set("X-Stackpanel-Token", token);
            return next(req);
          },
        ]
      : [],
  });
}

/**
 * Hook to get a Connect transport configured with the current agent context.
 */
export function useAgentTransport(): Transport {
  const { host, port, token } = useAgentContext();
  return useMemo(
    () => createAgentTransport(host, port, token ?? undefined),
    [host, port, token],
  );
}

/**
 * Hook to get a type-safe Connect client for the AgentService.
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const client = useConnectClient();
 *
 *   const handleClick = async () => {
 *     // Fully typed from proto
 *     const apps = await client.getApps({});
 *     console.log(apps.apps);
 *   };
 * }
 * ```
 */
export function useConnectClient() {
  const transport = useAgentTransport();
  return useMemo(() => createClient(AgentService, transport), [transport]);
}

// Re-export types from agent-client for convenience
export type { AgentServiceClient } from "@stackpanel/agent-client";
export { AgentService } from "@stackpanel/agent-client";
