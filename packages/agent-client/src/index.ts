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
import { ModuleService } from "@stackpanel/proto/agent/v1/module";

// Re-export all proto types for convenience
// These are from protobuf-ts which has nicer TypeScript interfaces
export * from "@stackpanel/proto";

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

export interface ModuleServiceClientConfig extends AgentClientConfig {
  /** Only read-only calls without a UI grant may use the agent's current/default project. */
  projectId?: string;
}

/** The Connect client type for AgentService */
export type AgentServiceClient = Client<typeof AgentService>;
export type ModuleServiceClient = Client<typeof ModuleService>;

// =============================================================================
// Client Factory
// =============================================================================

function agentTransport(
  { host = "localhost", port = 9876, token }: AgentClientConfig,
  projectId?: string,
) {
  return createConnectTransport({
    baseUrl: `http://${host}:${port}`,
    useBinaryFormat: false,
    interceptors: [
      (next) => (req) => {
        if (token) req.header.set("Authorization", `Bearer ${token}`);
        if (projectId) req.header.set("X-Stackpanel-Project", projectId);
        return next(req);
      },
    ],
  });
}

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
 * const client = createAgentClient({ port: 9876, token });
 *
 * // All methods are fully typed from proto
 * const apps = await client.getApps({});
 * const project = await client.getProject({});
 * ```
 */
export function createAgentClient(config: AgentClientConfig = {}): AgentServiceClient {
  return createClient(AgentService, agentTransport(config));
}

/**
 * Create a v1 module client scoped to the given agent credential and project.
 * Unary RPCs and server streams both use this scope. A panel's UI grant is a
 * per-call header, not an agent credential or a default on this client.
 *
 * @example
 * ```ts
 * const modules = createModuleServiceClient({ token, projectId });
 * const { modules: installed } = await modules.listModules({});
 * ```
 */
export function createModuleServiceClient(
  config: ModuleServiceClientConfig = {},
): ModuleServiceClient {
  return createClient(ModuleService, agentTransport(config, config.projectId));
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
export { AgentService, ModuleService };
