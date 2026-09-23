/**
 * MSW request handlers for the demo agent.
 *
 * The studio talks to the agent over two protocols, both of which terminate
 * as `fetch()` calls inside the browser so MSW can intercept them:
 *
 *   - REST          (AgentHttpClient)         GET/POST/DELETE `${baseUrl}/api/...`
 *   - Connect-RPC   (createAgentTransport)    POST `${baseUrl}/<service>/<Method>`
 *
 * Payload shapes follow the proto JSON mapping (camelCase) for RPC and the
 * Go `writeAPI` wrapper `{ success, data }` for REST, except where a handler
 * historically returned a bare object (`/health`, `/api/secrets/backend`).
 */

import { http, HttpResponse, passthrough } from "msw";
import {
	DEMO_BASE_URL,
	demoAppVariableLinks,
	demoAppsRpc,
	demoConfigRpc,
	demoEntities,
	demoFiles,
	demoGeneratedFiles,
	demoHealth,
	demoHealthSummary,
	demoInstalledPackages,
	demoNixConfig,
	demoNixConfigResponse,
	demoProcessComposeProcesses,
	demoProcessComposeState,
	demoProcessesRpc,
	demoProject,
	demoRecipients,
	demoRegistryModules,
	demoRestModules,
	demoRpcModules,
	demoRpcProject,
	demoSecretsRpc,
	demoSopsAgeKeysStatus,
	demoStateJson,
	demoTurboQueryResult,
	demoUsersRpc,
	demoVariablesRpc,
} from "./fixture";

const url = (path: string) => `${DEMO_BASE_URL}${path}`;
const ok = <T>(data: T) => HttpResponse.json({ success: true, data });

function nixConfigPayload() {
	return {
		...demoNixConfigResponse,
		configJson: JSON.stringify(demoNixConfig),
		lastUpdated: new Date().toISOString(),
	};
}

function connectResponse(method: string, body: Record<string, unknown>) {
	switch (method) {
		case "GetNixConfig":
		case "RefreshNixConfig":
			return nixConfigPayload();
		case "GetApps":
			return { apps: demoAppsRpc };
		case "SetApps":
			return body.apps ? body : { apps: demoAppsRpc };
		case "GetUsers":
			return { users: demoUsersRpc };
		case "SetUsers":
			return body.users ? body : { users: demoUsersRpc };
		case "GetVariables":
			return { variables: demoVariablesRpc };
		case "SetVariables":
			return body.variables ? body : { variables: demoVariablesRpc };
		case "GetSecrets":
			return demoSecretsRpc;
		case "SetSecrets":
			return Object.keys(body).length > 0 ? body : demoSecretsRpc;
		case "GetConfig":
			return demoConfigRpc;
		case "SetConfig":
			return Object.keys(body).length > 0 ? body : demoConfigRpc;
		case "GetProject":
			return { project: demoRpcProject };
		case "GetProcesses":
			return demoProcessesRpc;
		case "GetInstalledPackages":
			return demoInstalledPackages;
		case "GetModules":
			return { modules: demoRpcModules };
		case "GetModule": {
			const id = String(body.moduleId ?? "");
			return demoRpcModules[id] ?? { id, enable: false };
		}
		case "EnableModule":
		case "DisableModule":
		case "UpdateModuleSettings": {
			const id = String(body.moduleId ?? "");
			return {
				module: demoRpcModules[id] ?? { id, enable: method !== "DisableModule" },
				success: true,
				message: "demo (read-only)",
			};
		}
		case "GetHealthchecks":
			return {
				allHealthy: true,
				checks: Object.values(demoHealthSummary.modules).flatMap((mod) =>
					mod.checks.map((c) => ({
						name: c.check?.name ?? c.checkId,
						type: c.check?.type ?? "tcp",
						healthy: true,
						message: c.message,
						details: c.message,
					})),
				),
			};
		case "GetShellStatus":
			return {
				stale: false,
				rebuilding: false,
				lastBuilt: demoHealthSummary.lastUpdated,
				lastNixChange: demoHealthSummary.lastUpdated,
				changedFiles: [],
			};
		case "PatchNixData":
			return {
				success: true,
				updatedJson: JSON.stringify(demoEntities.apps),
				error: "",
			};
		case "GetAgeIdentity":
			return {
				type: "path",
				value: ".stack/keys/local.txt",
				keyPath: ".stack/keys/local.txt",
				publicKey: demoUsersRpc["demo-user"].publicKeys[0],
			};
		default:
			return {};
	}
}

export const demoHandlers = [
	// ---------------------------------------------------------------------------
	// Health + auth
	// ---------------------------------------------------------------------------
	http.get(url("/health"), () => HttpResponse.json(demoHealth)),
	http.get(url("/api/auth/validate"), () =>
		HttpResponse.json({ valid: true, agentId: demoHealth.agentId }),
	),

	http.get(url("/api/events"), () => new HttpResponse(null, { status: 204 })),

	// ---------------------------------------------------------------------------
	// Projects
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
	http.post(url("/api/project/close"), () => HttpResponse.json({ success: true })),
	http.delete(url("/api/project/remove"), () => HttpResponse.json({ success: true })),

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
	http.get(url("/api/nix/files"), () => ok(demoGeneratedFiles)),
	http.get(url("/api/state"), () => HttpResponse.json(demoStateJson)),

	// ---------------------------------------------------------------------------
	// Process-compose
	// ---------------------------------------------------------------------------
	http.get(url("/api/process-compose/processes"), () => ok(demoProcessComposeProcesses)),
	http.get(url("/api/process-compose/project/state"), () => ok(demoProcessComposeState)),

	// ---------------------------------------------------------------------------
	// Exec (turbo query + no-op shell)
	// ---------------------------------------------------------------------------
	http.post(url("/api/exec"), async ({ request }) => {
		const body = (await request.json().catch(() => ({}))) as {
			command?: string;
			args?: string[];
		};
		if (body.command === "turbo" && body.args?.[0] === "query") {
			return ok({
				exit_code: 0,
				stdout: JSON.stringify(demoTurboQueryResult),
				stderr: "",
			});
		}
		return ok({
			exit_code: 0,
			stdout: "[demo] command acknowledged (no real execution)\n",
			stderr: "",
		});
	}),

	// ---------------------------------------------------------------------------
	// Modules (REST)
	// ---------------------------------------------------------------------------
	http.get(url("/api/modules"), () =>
		ok({
			modules: demoRestModules,
			total: demoRestModules.length,
			enabled: demoRestModules.filter((m) => m.enabled).length,
			lastUpdated: demoHealthSummary.lastUpdated,
		}),
	),
	http.get(url("/api/modules/:name/config"), ({ params }) => {
		const name = String(params.name);
		const mod = demoRestModules.find((m) => m.id === name);
		return ok({
			enable: mod?.enabled ?? false,
			settings: {},
		});
	}),
	http.post(url("/api/modules/:name/config"), () =>
		ok({ success: true, message: "demo (read-only)" }),
	),
	http.post(url("/api/modules/:name/enable"), () =>
		ok({ success: true, message: "demo (read-only)" }),
	),
	http.get(url("/api/modules/:name"), ({ params }) => {
		const name = String(params.name);
		const mod = demoRestModules.find((m) => m.id === name);
		if (!mod) {
			return HttpResponse.json(
				{ success: false, error: `module not found: ${name}` },
				{ status: 404 },
			);
		}
		return ok({
			module: mod,
			config: { enable: mod.enabled, settings: {} },
		});
	}),
	http.get(url("/api/registry/modules"), () => ok(demoRegistryModules)),
	http.post(url("/api/registry/modules/install"), () =>
		ok({
			success: true,
			message: "Module install acknowledged (demo is read-only)",
			flakeInputCode: "",
			moduleImportCode: "",
		}),
	),

	// ---------------------------------------------------------------------------
	// Healthchecks, packages, apps links, files, secrets
	// ---------------------------------------------------------------------------
	http.get(url("/api/healthchecks"), () => ok(demoHealthSummary)),
	http.post(url("/api/healthchecks"), () => ok(demoHealthSummary)),
	http.get(url("/api/nixpkgs/installed"), () => ok(demoInstalledPackages)),
	http.get(url("/api/nixpkgs/search"), ({ request }) => {
		const q = (new URL(request.url).searchParams.get("q") ?? "").toLowerCase();
		const packages = demoInstalledPackages.packages.filter((p) =>
			p.name.toLowerCase().includes(q),
		);
		return ok({
			packages,
			total: packages.length,
			query: q,
			channel: "nixos-unstable",
		});
	}),
	http.get(url("/api/apps/links"), () => ok({ links: demoAppVariableLinks })),
	http.get(url("/api/files"), ({ request }) => {
		const path = new URL(request.url).searchParams.get("path") ?? "";
		const file = demoFiles[path];
		if (!file) {
			return ok({ path, content: "", exists: false });
		}
		return ok(file);
	}),
	http.post(url("/api/files"), () => ok({ ok: true })),
	http.get(url("/api/secrets/backend"), () => HttpResponse.json({ backend: "vals" })),
	http.get(url("/api/secrets/recipients"), () => ok(demoRecipients)),
	http.post(url("/api/secrets/recipients"), () => ok(demoRecipients.recipients[0])),
	http.get(url("/api/secrets/sops-age-keys/status"), () => ok(demoSopsAgeKeysStatus)),

	// ---------------------------------------------------------------------------
	// Connect-RPC
	// ---------------------------------------------------------------------------
	http.post(`${DEMO_BASE_URL}/:service/:method`, async ({ params, request }) => {
		const service = String(params.service ?? "");
		if (!service.includes(".")) return passthrough();
		const method = String(params.method ?? "");
		const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
		return HttpResponse.json(connectResponse(method, body));
	}),
];
