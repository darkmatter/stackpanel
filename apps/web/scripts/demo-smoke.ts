#!/usr/bin/env bun
/**
 * Standalone smoke test for the demo agent.
 *
 * Runs without the vitest harness so it can be invoked from any environment
 * that has bun installed (no `bun install` required for this single script —
 * msw is the only runtime dependency the handlers use, and it's already
 * pulled in by apps/web).
 *
 * Run: bun apps/web/scripts/demo-smoke.ts
 */

import { DEMO_BASE_URL, demoEntities, demoStateJson } from "../src/demo/fixture";
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
		const info = (h as unknown as { info: { method: string; path: string } })
			.info;
		if (info.method !== method) continue;
		if (info.path === target || info.path === path) return h;
	}
	throw new Error(`no handler for ${method} ${path}`);
}

async function main() {
	console.log("# demo agent smoke test");

	{
		console.log("GET /health");
		const res = await run(
			findHandler("GET", "/health"),
			new Request(`${DEMO_BASE_URL}/health`),
		);
		const body = (await res.json()) as { status: string; agentId: string };
		assert(body.status === "ok", `status === "ok" (got ${body.status})`);
		assert(
			body.agentId === "demo-agent",
			`agentId === "demo-agent" (got ${body.agentId})`,
		);
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
		assert(
			body.basePort === demoStateJson.basePort,
			`basePort === ${demoStateJson.basePort}`,
		);
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
	}

	{
		console.log("GET /api/process-compose/processes");
		const res = await run(
			findHandler("GET", "/api/process-compose/processes"),
			new Request(`${DEMO_BASE_URL}/api/process-compose/processes`),
		);
		const body = (await res.json()) as { processes: { name: string }[] };
		assert(body.processes.length > 0, "processes.length > 0");
		assert(
			body.processes.some((p) => p.name === "web"),
			"processes include `web`",
		);
	}

	if (failures > 0) {
		console.error(`\n${failures} assertion(s) failed`);
		process.exit(1);
	}
	console.log("\nall demo agent assertions passed");
}

await main();
