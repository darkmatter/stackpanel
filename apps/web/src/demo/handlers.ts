/**
 * MSW request handlers for the demo agent.
 *
 * The studio talks to the agent over two protocols, both of which terminate
 * as `fetch()` calls inside the browser so MSW can intercept them:
 *
 *   - REST          (AgentHttpClient)         GET/POST/DELETE `${baseUrl}/api/...`
 *   - Connect-RPC   (createAgentTransport)    POST `${baseUrl}/<service>/<method>`
 *
 * Endpoints below are hand-written stubs for the surface the studio actually
 * hits on first paint. The longer-term plan is to generate handlers from the
 * same `.proto.nix` schemas that already drive the Go agent and TS client —
 * tracked in beads under "proto-driven MSW handlers".
 *
 * Anything not handled here falls through `passthrough` and will fail; the
 * Studio panel that issued the request is responsible for surfacing a
 * sensible empty/error state. Add handlers as panels expose new gaps.
 */

import { http, HttpResponse, passthrough } from "msw";
import {
	DEMO_BASE_URL,
	demoEntities,
	demoHealth,
	demoNixConfig,
	demoProcessComposeProcesses,
	demoProject,
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

	// SSE: respond 204 so the EventSource fails fast and the AgentProvider
	// falls back to polling. Mocking a real event-stream is possible but noisy
	// and not required for the static demo.
	http.get(url("/api/events"), () => new HttpResponse(null, { status: 204 })),

	// ---------------------------------------------------------------------------
	// Projects (used by ProjectProvider on mount)
	// ---------------------------------------------------------------------------
	http.get(url("/api/project/list"), () =>
		HttpResponse.json({
			projects: [demoProject],
			default_path: demoProject.path,
		}),
	),
	http.get(url("/api/project/current"), () =>
		HttpResponse.json({
			has_project: true,
			project: demoProject,
			default_project: demoProject,
		}),
	),
	http.post(url("/api/project/open"), () =>
		HttpResponse.json({
			success: true,
			project: demoProject,
			devshell: { in_devshell: true, has_devshell_env: true },
		}),
	),
	http.post(url("/api/project/validate"), () =>
		HttpResponse.json({ valid: true, message: "demo project (read-only)" }),
	),
	http.post(url("/api/project/close"), () =>
		HttpResponse.json({ success: true }),
	),
	http.delete(url("/api/project/remove"), () =>
		HttpResponse.json({ success: true }),
	),

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
	// Process-compose (overview panel)
	// ---------------------------------------------------------------------------
	http.get(url("/api/process-compose/processes"), () =>
		HttpResponse.json(demoProcessComposeProcesses),
	),

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
