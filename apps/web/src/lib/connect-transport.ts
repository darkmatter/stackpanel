/**
 * Connect-RPC transport configuration for the Stackpanel agent.
 *
 * This provides type-safe RPC communication with the local agent using
 * the proto-generated service definitions.
 */

import type { Interceptor } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";

/**
 * Creates a Connect transport configured for the local agent.
 *
 * @param token - JWT auth token for the agent
 * @param port - Agent port (default 9876)
 */
export function createAgentTransport(token: string, port: number = 9876) {
	const authInterceptor: Interceptor = (next) => async (req) => {
		req.header.set("Authorization", `Bearer ${token}`);
		return next(req);
	};

	return createConnectTransport({
		baseUrl: `http://localhost:${port}`,
		// Use JSON for easier debugging (can switch to binary for production)
		useBinaryFormat: false,
		// Add auth header to all requests
		interceptors: [authInterceptor],
	});
}

/**
 * Default agent URL for development.
 */
export const DEFAULT_AGENT_URL = "http://localhost:9876";
