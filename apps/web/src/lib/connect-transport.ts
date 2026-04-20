/**
 * Connect-RPC transport configuration for the Stackpanel agent.
 *
 * This provides type-safe RPC communication with the local agent using
 * the proto-generated service definitions.
 */

import type { Interceptor } from "@connectrpc/connect";
import { ConnectError, Code } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { AGENT_AUTH_ERROR_EVENT } from "./agent";

/**
 * Creates a Connect transport configured for the local agent.
 *
 * @param token - JWT auth token for the agent
 * @param host - Agent host (default localhost)
 * @param port - Agent port (default 9876)
 */
export function createAgentTransport(
	token: string,
	host: string = "localhost",
	port: number = 9876,
) {
	const authInterceptor: Interceptor = (next) => async (req) => {
		req.header.set("Authorization", `Bearer ${token}`);
		try {
			return await next(req);
		} catch (err) {
			// Detect 401/Unauthenticated and dispatch auth error event
			if (err instanceof ConnectError && err.code === Code.Unauthenticated) {
				if (typeof window !== "undefined") {
					window.dispatchEvent(new CustomEvent(AGENT_AUTH_ERROR_EVENT));
				}
			}
			throw err;
		}
	};

	return createConnectTransport({
		baseUrl: `http://${host}:${port}`,
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
