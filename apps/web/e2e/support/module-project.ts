import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { JsonObject } from "@bufbuild/protobuf";
import { Code, ConnectError, createConnectRouter, type ServiceImpl } from "@connectrpc/connect";
import { createFetchHandler } from "@connectrpc/connect/protocol";
import type { Page } from "@playwright/test";
import { AgentService as ProjectData } from "@stackpanel/proto/agent-service";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import {
  PLAYWRIGHT_AGENT_PORT,
  PLAYWRIGHT_BASE_URL,
  PLAYWRIGHT_PROJECT_ROOT,
  PLAYWRIGHT_WEB_HOST,
} from "./constants";

/** Replace only project module state, never mutate the real E2E agent's flake. The generated
 * Connect server encodes the same typed messages and stream envelopes as the Go server. */
export async function serveModuleProject(page: Page) {
  const id = "status-board";
  const panelId = "status";
  const project = createHash("sha256")
    .update(realpathSync(PLAYWRIGHT_PROJECT_ROOT))
    .digest("hex")
    .slice(0, 8);
  const state = {
    installed: false,
    enabled: false,
    version: "",
    ref: "",
    searches: [] as string[],
    patches: [] as JsonObject[],
    actions: [] as string[],
    statusReads: [] as string[],
    proxyCalls: 0,
  };
  const adoption = { accepted: false, previewed: false };
  const offer = { id: "existing", revision: "5", type: "bool", label: "Use existing status file" };
  const settings: JsonObject = { greeting: "Hello" };
  const registry = () => ({
    id,
    slug: id,
    name: "Status board",
    category: "tools",
    latestVersion: "2",
    versions: [
      { version: "1", flakeUrl: "path:./status-board", ref: "v1" },
      { version: "2", flakeUrl: "path:./status-board", ref: "v2" },
    ],
    installed: state.installed,
    installedVersion: state.installed && !state.ref ? state.version : undefined,
  });
  const module = () => ({
    id,
    enabled: state.enabled,
    meta: { name: "Status board", category: "tools" },
    source: { type: "flake-input" },
    features: { files: true, services: true },
    settings,
    actions: {
      inspect: {
        label: "Inspect greeting",
        outputMode: "stream",
        argsSchema: { type: "object", properties: {}, additionalProperties: false },
      },
      status: {
        label: "App health",
        outputMode: "stream",
        argsSchema: {
          type: "object",
          properties: { app: { type: "string", enum: ["api", "web"] } },
          required: ["app"],
          additionalProperties: false,
        },
      },
    },
    configSchema: JSON.stringify({
      type: "object",
      properties: { greeting: { type: "string", title: "Greeting" } },
    }),
  });
  const panel = {
    id: panelId,
    title: "Greeting preview",
    enabled: true,
    order: 0,
    module: id,
    slot: "module",
    type: "PANEL_TYPE_CUSTOM",
    fields: [],
    apps: {},
    uiReview: { revision: "a".repeat(64) },
    uiBundle: {
      package: "fixture",
      entry: "index.html",
      permissions: ["config:read", "service:proxy"],
    },
  };
  const overview = {
    id: "app-health",
    module: id,
    title: "App health",
    type: "PANEL_TYPE_SPEC",
    slot: "module",
    enabled: true,
    order: 1,
    fields: [],
    apps: {},
    uiReview: { revision: "b".repeat(64) },
    spec: {
      root: "workspace",
      state: { local: { app: "api" } },
      elements: {
        workspace: { type: "Stack", props: {}, children: ["app", "live", "actions"] },
        app: {
          type: "AppPicker",
          props: {
            label: "Inspect app",
            apps: ["api", "web"],
            value: { $bindState: "/local/app" },
          },
        },
        live: { type: "StatusView", props: { action: "status", app: { $state: "/local/app" } } },
        actions: { type: "Actions", props: { ids: ["inspect"] } },
      },
    },
  };
  const ticket = `/api/v1/modules/${id}/ui/${panelId}/_ticket/${"x".repeat(40)}`;
  const router = createConnectRouter({ grpc: false, grpcWeb: false });
  function checkId(value: string) {
    if (value !== id) throw new ConnectError("Unknown module", Code.NotFound);
  }
  const methods = {
    listRegistryModules({ query }) {
      state.searches.push(query);
      return {
        modules: !query || "status board".includes(query.toLowerCase()) ? [registry()] : [],
      };
    },
    getRegistryModule({ moduleId }) {
      checkId(moduleId);
      return { module: registry(), readme: "# Status guide" };
    },
    installModule({ moduleId, version, ref }) {
      checkId(moduleId);
      Object.assign(state, { installed: true, version, ref });
      return { moduleId: id, message: "Input locked" };
    },
    listModules: () => ({ modules: state.installed ? [module()] : [] }),
    getModule({ moduleId }, ctx) {
      if (ctx.requestHeader.has("X-Stackpanel-UI-Grant"))
        throw new ConnectError("Panel grants cannot read module details", Code.PermissionDenied);
      checkId(moduleId);
      if (!state.installed) throw new ConnectError("Module not installed", Code.NotFound);
      return { module: module() };
    },
    previewModuleEnable({ moduleId, answers }) {
      checkId(moduleId);
      const choice = answers[0];
      adoption.previewed =
        choice?.id === offer.id &&
        choice.revision === offer.revision &&
        choice.answer?.kind.case === "boolValue" &&
        choice.answer.kind.value;
      return {
        preview: {
          files: { added: [adoption.previewed ? "adopted-status.json" : "status.json"] },
          packages: {},
          services: {},
          offers: [offer],
        },
      };
    },
    enableModule({ moduleId, answers }) {
      checkId(moduleId);
      const choice = answers[0];
      if (
        !adoption.previewed ||
        answers.length !== 1 ||
        choice?.id !== offer.id ||
        choice.revision !== offer.revision ||
        choice.answer?.kind.case !== "boolValue" ||
        !choice.answer.kind.value
      ) {
        throw new ConnectError("Expected the reviewed adoption choice", Code.FailedPrecondition);
      }
      adoption.accepted = true;
      state.enabled = true;
      return { message: "Status board enabled" };
    },
    getModuleOutputs({ moduleId }) {
      checkId(moduleId);
      return {
        outputs: {
          moduleId,
          files: [{ path: "status.json" }],
          services: [{ name: "health", proxyEnabled: true }],
        },
      };
    },
    updateModuleConfig({ moduleId, settings: patch }) {
      checkId(moduleId);
      if (!patch) throw new ConnectError("No settings supplied", Code.InvalidArgument);
      Object.assign(settings, patch);
      state.patches.push(patch);
      return { message: "Greeting saved" };
    },
    async *runModuleAction({ moduleId, actionId, args }, ctx) {
      checkId(moduleId);
      if (actionId === "status") {
        const app = args?.app;
        if (
          ctx.requestHeader.get("X-Stackpanel-UI-Grant") !== "fixture-status" ||
          (app !== "api" && app !== "web")
        ) {
          throw new ConnectError("Wrong status grant or app", Code.PermissionDenied);
        }
        state.statusReads.push(app);
        yield { event: { case: "stdout", value: `${app}: healthy` } };
        yield { event: { case: "exitCode", value: 0 } };
        return;
      }
      state.actions.push(actionId);
      if (typeof settings.greeting !== "string")
        throw new ConnectError("Invalid greeting", Code.InvalidArgument);
      yield { event: { case: "stdout", value: `greeting=${settings.greeting}` } };
      yield { event: { case: "stderr", value: "inspection complete" } };
      yield { event: { case: "exitCode", value: 0 } };
    },
    openModuleUI({ moduleId, panelId: requested, reviewRevision, statusAction, statusApps }, ctx) {
      checkId(moduleId);
      if (state.enabled && requested === overview.id) {
        if (
          reviewRevision !== overview.uiReview.revision ||
          statusAction !== "status" ||
          statusApps.length !== 1 ||
          statusApps[0] !== "web"
        )
          throw new ConnectError("Unexpected status approval", Code.PermissionDenied);
        ctx.responseHeader.set("X-Stackpanel-UI-Grant", "fixture-status");
        ctx.responseHeader.set(
          "X-Stackpanel-UI-Expires-At",
          String(Math.floor(Date.now() / 1000) + 300),
        );
        return {
          reviewRevision,
          permissions: ["actions:run"],
          actionIds: ["status"],
          actions: { status: module().actions.status },
        };
      }
      if (!state.enabled || requested !== panelId)
        throw new ConnectError("Panel unavailable", Code.NotFound);
      if (ctx.requestHeader.has("X-Stackpanel-UI-Grant")) {
        if (ctx.requestHeader.get("X-Stackpanel-UI-Grant") !== "fixture-binding")
          throw new ConnectError("Invalid document grant", Code.PermissionDenied);
        return { reviewRevision: panel.uiReview.revision, settings };
      }
      if (reviewRevision !== panel.uiReview.revision)
        throw new ConnectError("Stale document review", Code.PermissionDenied);
      ctx.responseHeader.set("X-Stackpanel-UI-Grant", "fixture-binding");
      ctx.responseHeader.set(
        "X-Stackpanel-UI-Expires-At",
        String(Math.floor(Date.now() / 1000) + 300),
      );
      return {
        reviewRevision,
        settings,
        url: `${ticket}/index.html`,
        permissions: ["config:read", "service:proxy"],
      };
    },
  } satisfies Partial<ServiceImpl<typeof ModuleService>>;
  router.service(ModuleService, methods);
  router.rpc(ProjectData.method.getNixConfig, () => ({
    configJson: JSON.stringify({
      modulesListAll: state.installed ? [module()] : [],
      panelsList: state.enabled ? [panel, overview] : [],
    }),
  }));
  await page.addInitScript(
    ({ key, project }) => {
      if (window.top === window) sessionStorage.setItem(key, project);
    },
    { key: `stackpanel.agent.project:${PLAYWRIGHT_WEB_HOST}:${PLAYWRIGHT_AGENT_PORT}`, project },
  );
  const agentOrigin = `http://${PLAYWRIGHT_WEB_HOST}:${PLAYWRIGHT_AGENT_PORT}`;
  const cors = {
    "access-control-allow-origin": PLAYWRIGHT_BASE_URL,
    "access-control-allow-methods": "POST, GET, OPTIONS",
    "access-control-allow-headers":
      "Authorization, Content-Type, Connect-Protocol-Version, Connect-Timeout-Ms, X-Stackpanel-Project, X-Stackpanel-UI-Grant, X-User-Agent",
    "access-control-expose-headers": "X-Stackpanel-UI-Grant, X-Stackpanel-UI-Expires-At",
  };
  for (const handler of router.handlers) {
    const handle = createFetchHandler(handler, { httpVersion: "1.1" });
    await page.route(
      (url) => url.origin === agentOrigin && url.pathname === handler.requestPath,
      async (route) => {
        const req = route.request();
        if (req.method() === "OPTIONS") return route.fulfill({ status: 204, headers: cors });
        if ((await req.headerValue("x-stackpanel-project")) !== project) {
          throw new Error(`Missing project selector on ${handler.method.name}`);
        }
        const body = req.postDataBuffer();
        const response = await handle(
          new Request(req.url(), {
            method: req.method(),
            headers: req.headers(),
            body: body && Uint8Array.from(body),
          }),
        );
        await route.fulfill({
          status: response.status,
          headers: { ...Object.fromEntries(response.headers), ...cors },
          body: Buffer.from(await response.arrayBuffer()),
        });
      },
    );
  }
  await page.route(
    `${agentOrigin}/api/v1/modules/${id}/services/health/proxy/status`,
    async (route) => {
      if (route.request().method() === "OPTIONS")
        return route.fulfill({ status: 204, headers: cors });
      if ((await route.request().headerValue("x-stackpanel-ui-grant")) !== "fixture-binding") {
        return route.fulfill({ status: 403, headers: cors });
      }
      state.proxyCalls++;
      return route.fulfill({
        body: "Local service is ready",
        headers: { ...cors, "content-type": "text/plain", "x-stackpanel-service-response": "1" },
      });
    },
  );
  const entry = fileURLToPath(new URL("./status-panel.ts", import.meta.url));
  const bundle = execFileSync("bun", ["build", entry, "--target=browser", "--format=iife"], {
    encoding: "utf8",
  });
  await page.route(
    (url) => url.pathname === `${ticket}/index.html`,
    (route) =>
      route.fulfill({
        contentType: "text/html",
        body: '<!doctype html><body><script src="panel.js" defer></script></body>',
      }),
  );
  await page.route(
    (url) => url.pathname === `${ticket}/panel.js`,
    (route) => route.fulfill({ contentType: "text/javascript", body: bundle }),
  );
  return state;
}
