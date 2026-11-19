#!/usr/bin/env bun
/**
 * Standalone smoke test for the demo agent.
 *
 * Exercises the MSW handlers without starting a browser or a live agent.
 *
 * Run: bun apps/web/scripts/demo-smoke.ts
 */

import { Code, ConnectError, createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { DEMO_BASE_URL, demoEntities, demoProject, demoStateJson } from "../src/demo/fixture";
import { demoHandlers } from "../src/demo/handlers";

type AnyHandler = (typeof demoHandlers)[number];

let failures = 0;

function assert(cond: unknown, label: string): void {
  if (cond) {
    console.log(`  ok  ${label}`);
  } else {
    failures++;
    console.error(`  FAIL ${label}`);
  }
}

async function run(handler: AnyHandler, request: Request): Promise<Response> {
  const result = await (
    handler as unknown as {
      run: (args: { request: Request }) => Promise<{ response: Response } | null>;
    }
  ).run({ request });
  if (!result) throw new Error(`handler did not match: ${request.url}`);
  return result.response;
}

function findHandler(method: string, path: string): AnyHandler {
  const target = `${DEMO_BASE_URL}${path}`;
  for (const h of demoHandlers) {
    const info = (h as unknown as { info: { method: string; path: string } }).info;
    if (info.method !== method) continue;
    if (info.path === target || info.path === path) return h;
  }
  throw new Error(`no handler for ${method} ${path}`);
}

async function main() {
  console.log("# demo agent smoke test");

  {
    console.log("GET /health");
    const res = await run(findHandler("GET", "/health"), new Request(`${DEMO_BASE_URL}/health`));
    const body = (await res.json()) as { status: string; agentId: string };
    assert(body.status === "ok", `status === "ok" (got ${body.status})`);
    assert(body.agentId === "demo-agent", `agentId === "demo-agent" (got ${body.agentId})`);
  }

  {
    console.log("GET /api/state");
    const res = await run(
      findHandler("GET", "/api/state"),
      new Request(`${DEMO_BASE_URL}/api/state`),
    );
    const body = (await res.json()) as typeof demoStateJson;
    assert(
      body.projectName === demoStateJson.projectName,
      `projectName === "${demoStateJson.projectName}"`,
    );
    assert(body.basePort === demoStateJson.basePort, `basePort === ${demoStateJson.basePort}`);
    assert(Object.keys(body.apps).includes("web"), "apps include `web`");
  }

  {
    console.log("GET /api/nix/data?entity=apps");
    const res = await run(
      findHandler("GET", "/api/nix/data"),
      new Request(`${DEMO_BASE_URL}/api/nix/data?entity=apps`),
    );
    const body = (await res.json()) as {
      success: boolean;
      data: { entity: string; exists: boolean; data: unknown };
    };
    assert(body.success === true, "success === true");
    assert(body.data.entity === "apps", `entity === "apps"`);
    assert(body.data.exists === true, "exists === true");
    assert(
      JSON.stringify(body.data.data) === JSON.stringify(demoEntities.apps),
      "data matches demoEntities.apps",
    );
    const oldRead = await run(findHandler("GET", "/api/nix/data"),
      new Request(`${DEMO_BASE_URL}/api/nix/data?entity=modules`));
    const oldWrite = await run(findHandler("POST", "/api/nix/data"),
      new Request(`${DEMO_BASE_URL}/api/nix/data`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ entity: "modules", key: "fly", data: {} }),
      }));
    assert(oldRead.status === 400 && oldWrite.status === 400, "modules are not a generic Nix data entity");
  }

  {
    console.log("GET /api/process-compose/processes");
    const res = await run(
      findHandler("GET", "/api/process-compose/processes"),
      new Request(`${DEMO_BASE_URL}/api/process-compose/processes`),
    );
    const body = (await res.json()) as {
      success: boolean;
      data: { processes: { name: string }[] };
    };
    assert(body.success === true, "success === true");
    assert(body.data.processes.length > 0, "processes.length > 0");
    assert(
      body.data.processes.some((p) => p.name === "web"),
      "processes include `web`",
    );
  }

  {
    console.log("POST Connect GetNixConfig");
    const res = await run(
      findHandler("POST", "/:service/:method"),
      new Request(`${DEMO_BASE_URL}/stackpanel.agent.AgentService/GetNixConfig`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ refresh: false }),
      }),
    );
    const body = (await res.json()) as { configJson?: string };
    assert(typeof body.configJson === "string", "configJson is a string");
    const config = JSON.parse(body.configJson ?? "{}") as {
      projectName: string;
      modulesListAll: { id: string; enabled: boolean }[];
      panelsList: { id: string; module: string; slot: string }[];
    };
    assert(
      config.projectName === "stackpanel-demo",
      `projectName === stackpanel-demo (got ${config.projectName})`,
    );
    const enabled = new Set(config.modulesListAll.filter((mod) => mod.enabled).map((mod) => mod.id));
    assert(config.panelsList.every((panel) => panel.slot && enabled.has(panel.module)),
      "every mounted panel declares its slot and an enabled owner");
    assert(config.panelsList.some((panel) => panel.module === "fly" && panel.slot === "app:deployment"),
      "Fly.io app settings belong to the installed Fly module");
    assert(!["panels", "panelModules", "panelsComputed", "ui"].some((key) => key in config),
      "evaluated config does not publish duplicate panel or module catalogs");
  }

  {
    console.log("Connect module lifecycle");
    const transport = createConnectTransport({
      baseUrl: DEMO_BASE_URL,
      useBinaryFormat: false,
      interceptors: [(next) => (request) => {
        request.header.set("X-Stackpanel-Project", demoProject.id);
        return next(request);
      }],
      fetch: Object.assign(
        (...args: Parameters<typeof fetch>) => {
          const request = new Request(...args);
          return run(findHandler(request.method, new URL(request.url).pathname), request);
        },
        { preconnect: fetch.preconnect },
      ),
    });
    const client = createClient(ModuleService, transport);
    assert(
      (await client.listModules({})).modules.some((mod) => mod.enabled),
      "lists enabled modules",
    );
    const { modules } = await client.listRegistryModules({ query: "playwright", tag: "browser" });
    const entry = modules[0];
    if (!entry || !entry.versions[1]) throw new Error("Missing versioned Playwright demo fixture");
    const moduleId = entry.slug;
    await client.installModule({ moduleId, version: entry.versions[1].version });
    assert(
      (await client.getModule({ moduleId })).module?.enabled === false,
      "install does not enable",
    );
    assert((await client.getRegistryModule({ moduleId })).module?.installedVersion === entry.versions[1].version,
      "the registry reports the selected catalog pin independently of enablement");
    const { preview } = await client.previewModuleEnable({ moduleId });
    const offer = preview?.offers[0];
    if (!offer || preview?.files?.added.includes("playwright.config.ts"))
      throw new Error("Optional file must need an explicit choice");
    const choice = {
      id: offer.id,
      revision: offer.revision,
      answer: { kind: { case: "boolValue" as const, value: true } },
    };
    const answers = [choice];
    const reviewed = await client.previewModuleEnable({ moduleId, answers });
    assert(
      reviewed.preview?.files?.added.includes("playwright.config.ts"),
      "selected plan includes the optional file",
    );
    try {
      await client.enableModule({ moduleId, answers: [{ ...choice, revision: "stale" }] });
      assert(false, "rejects a stale adoption revision");
    } catch (error) {
      assert(error instanceof ConnectError && error.code === Code.FailedPrecondition,
        "rejects a stale adoption revision");
    }
    await client.enableModule({ moduleId, answers });
    await client.updateModuleConfig({
      moduleId,
      settings: { "demo.key": "literal", runner: { workers: 2 } },
    });
    await client.updateModuleConfig({ moduleId, settings: { runner: { retries: 1 } } });
    await client.updateModule({ moduleId, version: entry.latestVersion, ref: "demo-branch" });
    const detail = await client.getModule({ moduleId });
    assert(
      detail.module?.settings?.["demo.key"] === "literal",
      "update preserves literal setting keys",
    );
    const runner = detail.module?.settings?.runner;
    assert(
      runner &&
        typeof runner === "object" &&
        !Array.isArray(runner) &&
        runner.workers === 2 &&
        runner.retries === 1,
      "settings patches preserve nested siblings",
    );
    assert(detail.module?.source?.ref === "demo-branch", "update persists the ref override");
    const updated = (await client.getRegistryModule({ moduleId })).module;
    assert(updated?.installed && updated.installedVersion === undefined,
      "a custom ref remains installed without inventing a catalog version");
    assert(
      (await client.getModuleOutputs({ moduleId })).outputs?.files.some(
        (file) => file.path === "playwright.config.ts",
      ),
      "enabled module contributes outputs",
    );
    try {
      const bound = client.runModuleAction({ moduleId, actionId: "inspect" }, {
        headers: { "X-Stackpanel-UI-Grant": "unissued-demo-grant" },
      });
      await bound[Symbol.asyncIterator]().next();
      assert(false, "rejects unissued panel grants");
    } catch (error) {
      assert(error instanceof ConnectError && error.code === Code.PermissionDenied,
        "rejects unissued panel grants instead of running as the host");
    }
    const events = [];
    for await (const response of client.runModuleAction({ moduleId, actionId: "inspect" }))
      events.push(response.event);
    assert(events.some((event) => event.case === "stdout" && event.value.includes('"workers": 2')) &&
      events.some((event) => event.case === "exitCode" && event.value === 0),
      "the declared inspect action streams this module's current settings and exits");
    await client.disableModule({ moduleId });
    assert((await client.getModuleOutputs({ moduleId })).outputs?.files.length === 0,
      "disable removes the contribution without uninstalling the module");
    await client.uninstallModule({ moduleId });
    assert(
      (await client.getRegistryModule({ moduleId })).module?.installed === false,
      "uninstall clears registry state",
    );
    try {
      await client.getModule({ moduleId });
      assert(false, "uninstalled module is absent");
    } catch (error) {
      assert(
        error instanceof ConnectError && error.code === Code.NotFound,
        "uninstalled module is absent",
      );
    }
  }

  {
    console.log("GET /api/healthchecks");
    const res = await run(
      findHandler("GET", "/api/healthchecks"),
      new Request(`${DEMO_BASE_URL}/api/healthchecks`),
    );
    const body = (await res.json()) as {
      success: boolean;
      data: { overallStatus: string; totalHealthy: number };
    };
    assert(body.success === true, "success === true");
    assert(
      body.data.overallStatus === "HEALTH_STATUS_HEALTHY",
      `overallStatus healthy (got ${body.data.overallStatus})`,
    );
    assert(body.data.totalHealthy > 0, "totalHealthy > 0");
  }

  if (failures > 0) {
    console.error(`\n${failures} assertion(s) failed`);
    process.exit(1);
  }
  console.log("\nall demo agent assertions passed");
}

await main();
