/**
 * MSW request handlers for the demo agent.
 *
 * The studio talks to the agent over two protocols, and both terminate as
 * `fetch()` calls so MSW can intercept them:
 *   - REST  (AgentHttpClient)         GET/POST `${baseUrl}/api/...`
 *   - Connect-RPC (createAgentTransport) POST `${baseUrl}/<service>/<method>`
 *
 * For now we hand-write a handful of high-traffic REST handlers and a
 * Connect-RPC catch-all that returns empty-but-shaped responses. The longer-
 * term plan is to generate handler stubs from the same `.proto` files that
 * already drive the Go agent and the TS client.
 */

import { http, HttpResponse, passthrough } from "msw";
import {
	DEMO_BASE_URL,
	demoEntities,
	demoHealth,
	demoNixConfig,
	demoStateJson,
} from "./fixture";

const url = (path: string) => `${DEMO_BASE_URL}${path}`;

const ok = <T>(data: T) => HttpResponse.json({ success: true, data });

export const demoHandlers = [
	// ---------------------------------------------------------------------------
	// Health + auth
	// ---------------------------------------------------------------------------
	http.get(url("/health"), () => HttpResponse.json(demoHealth)),
	http.get(url("/api/auth/validate"), () =>
		HttpResponse.json({ valid: true, agentId: demoHealth.agentId }),
	),

	// SSE: respond 204 so the EventSource fails fast and the provider falls
	// back to polling. Mocking a real event-stream is possible but noisier.
	http.get(url("/api/events"), () => new HttpResponse(null, { status: 204 })),

	// ---------------------------------------------------------------------------
	// Nix config + entity data
	// ---------------------------------------------------------------------------
	http.get(url("/api/nix/config"), () =>
		ok({
			config: demoNixConfig,
			last_updated: new Date().toISOString(),
			cached: true,
			source: "demo",
		}),
	),
	http.post(url("/api/nix/config"), () =>
		ok({
			config: demoNixConfig,
			last_updated: new Date().toISOString(),
			refreshed: true,
			source: "demo",
		}),
	),

	http.get(url("/api/nix/data"), ({ request }) => {
		const entity = new URL(request.url).searchParams.get("entity") ?? "";
		const data = demoEntities[entity];
		return ok({
			entity,
			exists: data !== undefined,
			data: data ?? null,
		});
	}),
	http.post(url("/api/nix/data"), () =>
		HttpResponse.json({ success: true, path: "demo (read-only)" }),
	),

	http.get(url("/api/state"), () => HttpResponse.json(demoStateJson)),

	// ---------------------------------------------------------------------------
	// Process / service control: accept and no-op so the UI feels responsive
	// ---------------------------------------------------------------------------
	http.post(url("/api/exec"), () =>
		HttpResponse.json({
			success: true,
			data: {
				exitCode: 0,
				stdout: "[demo] command acknowledged (no real execution)\n",
				stderr: "",
			},
		}),
	),

	// ---------------------------------------------------------------------------
	// Connect-RPC catch-all
	//
	// Connect uses POST to `/<fully.qualified.Service>/<Method>`. Returning an
	// empty JSON object keeps most queries from throwing; specific methods can
	// be peeled off into dedicated handlers as the demo grows.
	// ---------------------------------------------------------------------------
	http.post(`${DEMO_BASE_URL}/:service/:method`, ({ params }) => {
		const service = String(params.service ?? "");
		// Only intercept Connect-style service paths (contain a dot)
		if (!service.includes(".")) return passthrough();
		return HttpResponse.json({});
	}),
];
