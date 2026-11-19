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
import { canonicalAgentOrigin, fetchWithAgentIdentity } from "./agent-identity";
import { AgentService } from "@stackpanel/proto/agent/v1/agent";
import { ProjectService } from "@stackpanel/proto/agent/v1/project";

/**
 * Creates a Connect transport configured for the local agent.
 *
 * @param token - An authenticated agent credential; without one calls fail locally.
 * @param host - Agent host (default localhost)
 * @param port - Agent port (default 9876)
 * @param projectId - Immutable selection required for project-scoped v1 services.
 */
export function createAgentTransport(
	token: string | null | undefined,
	host: string = "localhost",
	port: number = 9876,
	projectId?: string | null,
) {
	const origin = canonicalAgentOrigin(host, port);
	const authInterceptor: Interceptor = (next) => async (req) => {
		if (!token) throw new ConnectError("Pair with the agent first", Code.Unauthenticated);
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

	const projectInterceptor: Interceptor = (next) => (req) => {
		if (!projectId?.trim() && req.service.typeName !== AgentService.typeName &&
			req.service.typeName !== ProjectService.typeName) {
			throw new ConnectError("Select a project first", Code.FailedPrecondition);
		}
		if (projectId) req.header.set("X-Stackpanel-Project", projectId);
		return next(req);
	};

	return createConnectTransport({
		baseUrl: origin,
		fetch: Object.assign((input: RequestInfo | URL, init?: RequestInit) => {
			if (!token) throw new ConnectError("Pair with the agent first", Code.Unauthenticated);
			return fetchWithAgentIdentity(origin, token, input, init);
		}, { preconnect: globalThis.fetch.preconnect }),
		// Use JSON for easier debugging (can switch to binary for production)
		useBinaryFormat: false,
		interceptors: [authInterceptor, projectInterceptor],
	});
}

/**
 * Default agent URL for development.
 */
export const DEFAULT_AGENT_URL = "http://localhost:9876";
