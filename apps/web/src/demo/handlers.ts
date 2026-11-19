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
import { demoConnectHandlers, demoEvaluatedConfig } from "./connect-handlers";
import {
  DEMO_BASE_URL,
  demoAppVariableLinks,
  demoAppsRpc,
  demoEntities,
  demoFiles,
  demoGeneratedFiles,
  demoHealth,
  demoHealthSummary,
  demoInstalledPackages,
  demoProcessComposeProcesses,
  demoProcessComposeState,
  demoProcessesRpc,
  demoProject,
  demoRecipients,
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

const moduleEntities = { modules: true, "external-modules": true };
const moduleDataMessage = "modules are managed by ModuleService, not a data entity";

function moduleDataError(entity: unknown) {
  if (typeof entity === "string" && Object.hasOwn(moduleEntities, entity.trim()))
    return HttpResponse.json({ success: false, error: moduleDataMessage }, { status: 400 });
  return undefined;
}

function nixConfigPayload() {
  return {
    cached: true,
    source: "demo",
    configJson: JSON.stringify(demoEvaluatedConfig()),
    lastUpdated: new Date().toISOString(),
  };
}

function connectResponse(method: string) {
  switch (method) {
    case "GetNixConfig":
      return nixConfigPayload();
    case "GetApps":
      return { apps: demoAppsRpc };
    case "GetUsers":
      return { users: demoUsersRpc };
    case "GetVariables":
      return { variables: demoVariablesRpc };
    case "GetSecrets":
      return demoSecretsRpc;
    case "GetProject":
      return { project: demoRpcProject };
    case "GetProcesses":
      return demoProcessesRpc;
    case "GetInstalledPackages":
      return demoInstalledPackages;
    default:
      return undefined;
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
      config: demoEvaluatedConfig(),
      last_updated: new Date().toISOString(),
      cached: true,
      source: "demo",
    }),
  ),
  http.post(url("/api/nix/config"), () =>
    ok({
      config: demoEvaluatedConfig(),
      last_updated: new Date().toISOString(),
      refreshed: true,
      source: "demo",
    }),
  ),
  http.get(url("/api/nix/data"), ({ request }) => {
    const entity = new URL(request.url).searchParams.get("entity")?.trim() ?? "";
    const error = moduleDataError(entity);
    if (error) return error;
    const data = demoEntities[entity];
    return ok({
      entity,
      exists: data !== undefined,
      data: data ?? null,
    });
  }),
  http.post(url("/api/nix/data"), async ({ request }) => {
    const body = await request.json();
    if (!body || typeof body !== "object" || !("entity" in body))
      return HttpResponse.json({ success: false, error: "entity is required" }, { status: 400 });
    return (
      moduleDataError(body.entity) ?? HttpResponse.json({ success: true, path: "demo (read-only)" })
    );
  }),
  http.delete(
    url("/api/nix/data"),
    ({ request }) =>
      moduleDataError(new URL(request.url).searchParams.get("entity")?.trim()) ?? passthrough(),
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
  // Healthchecks, packages, apps links, files, secrets
  // ---------------------------------------------------------------------------
  http.get(url("/api/healthchecks"), () => ok(demoHealthSummary)),
  http.post(url("/api/healthchecks"), () => ok(demoHealthSummary)),
  http.get(url("/api/nixpkgs/installed"), () => ok(demoInstalledPackages)),
  http.get(url("/api/nixpkgs/search"), ({ request }) => {
    const q = (new URL(request.url).searchParams.get("q") ?? "").toLowerCase();
    const packages = demoInstalledPackages.packages.filter((p) => p.name.toLowerCase().includes(q));
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
  ...demoConnectHandlers,
  http.post(`${DEMO_BASE_URL}/:service/:method`, async ({ params, request }) => {
    const service = String(params.service ?? "");
    if (!service.includes(".")) return passthrough();
    const method = String(params.method ?? "");
    if (service === "stackpanel.agent.AgentService") {
      const id = request.headers.get("X-Stackpanel-Project");
      if (id && id !== demoProject.id)
        return HttpResponse.json(
          { code: "not_found", message: `Unknown demo project: ${id}` },
          { status: 404 },
        );
      if (method === "PatchNixData" && request.headers.get("content-type")?.includes("json")) {
        const patch = await request.json();
        if (
          patch &&
          typeof patch === "object" &&
          "entity" in patch &&
          typeof patch.entity === "string" &&
          Object.hasOwn(moduleEntities, patch.entity.trim())
        ) {
          return HttpResponse.json(
            { code: "invalid_argument", message: moduleDataMessage },
            { status: 400 },
          );
        }
      }
    }
    const response =
      service === "stackpanel.agent.AgentService" ? connectResponse(method) : undefined;
    if (response !== undefined) return HttpResponse.json(response);
    return HttpResponse.json(
      { code: "unimplemented", message: `Demo does not implement ${service}/${method}` },
      { status: 501 },
    );
  }),
];
