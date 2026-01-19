/**
 * @stackpanel/agent-client
 *
 * Type-safe client for communicating with the Stackpanel agent.
 * Uses Connect-RPC for fully typed request/response handling.
 *
 * All types are generated from proto definitions - no manual type definitions needed.
 */

import { createClient, type Client } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
// Import the bufbuild-generated service descriptor (required for Connect)
import { AgentService } from "@stackpanel/proto/agent-service";

// Re-export all proto types for convenience
// These are from protobuf-ts which has nicer TypeScript interfaces
export * from "@stackpanel/proto";
export * from "@stackpanel/proto/agent";
export * from "@stackpanel/proto/apps";
export * from "@stackpanel/proto/variables";
export * from "@stackpanel/proto/users";
export * from "@stackpanel/proto/services";
export * from "@stackpanel/proto/tasks";
export * from "@stackpanel/proto/files";
export * from "@stackpanel/proto/config";
export * from "@stackpanel/proto/secrets";
export * from "@stackpanel/proto/aws";

// =============================================================================
// Client Types
// =============================================================================

export interface AgentClientConfig {
  /** Agent host (default: localhost) */
  host?: string;
  /** Agent port (default: 9876) */
  port?: number;
  /** Authentication token */
  token?: string;
}

/** The Connect client type for AgentService */
export type AgentServiceClient = Client<typeof AgentService>;

// =============================================================================
// Client Factory
// =============================================================================

/**
 * Create a type-safe client for the Stackpanel agent.
 *
 * Uses Connect-RPC protocol which provides:
 * - Fully typed request/response from proto definitions
 * - Automatic serialization/deserialization
 * - Proper error handling with Connect error codes
 *
 * @example
 * ```ts
 * const client = createAgentClient({ port: 9876 });
 *
 * // All methods are fully typed from proto
 * const apps = await client.getApps({});
 * const project = await client.getProject({});
 *
 * // Write operations are also typed
 * await client.setApps({ apps: { myApp: { name: "My App", path: "./apps/myapp" } } });
 * ```
 */
export function createAgentClient(config: AgentClientConfig = {}): AgentServiceClient {
  const host = config.host ?? "localhost";
  const port = config.port ?? 9876;
  const baseUrl = `http://${host}:${port}`;

  const transport = createConnectTransport({
    baseUrl,
    // Use JSON for easier debugging; can switch to binary for performance
    useBinaryFormat: false,
    // Add auth header if token is provided
    interceptors: config.token
      ? [
          (next) => async (req) => {
            req.header.set("X-Stackpanel-Token", config.token!);
            return next(req);
          },
        ]
      : [],
  });

  return createClient(AgentService, transport);
}

// =============================================================================
// React Query Integration
// =============================================================================

/**
 * Get query options for TanStack Query integration.
 *
 * The proto package already exports TanStack Query hooks from:
 * `@stackpanel/proto/agent-connect`
 *
 * Use those directly with a transport provider:
 *
 * @example
 * ```tsx
 * import { TransportProvider } from "@connectrpc/connect-query";
 * import { getApps } from "@stackpanel/proto/agent-connect";
 *
 * // In your app root
 * <TransportProvider transport={transport}>
 *   <App />
 * </TransportProvider>
 *
 * // In a component
 * const { data: apps } = useQuery(getApps);
 * ```
 */
export { AgentService };
