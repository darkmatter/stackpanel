import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

const landingEntrypoints = [
	"src/components/landing/hero-section.tsx",
	"src/components/landing/cta-section.tsx",
	"src/components/landing/header.tsx",
	"src/components/landing/waitlist-dialog.tsx",
];

function readWebFile(path: string): string {
	return readFileSync(resolve(webRoot, path), "utf8");
}

describe("studio demo regression coverage", () => {
	it("routes landing demo entrypoints directly to studio with demo mode enabled", () => {
		for (const entrypoint of landingEntrypoints) {
			const source = readWebFile(entrypoint);

			expect(source).not.toContain('to="/demo"');
			expect(source).not.toContain('href: "/demo"');
		}
	});

	it("accepts the production-parsed numeric demo query value", () => {
		const source = readWebFile("src/routes/studio.tsx");

		expect(source).toContain("search.demo === 1");
	});

	it("serves an MSW worker generated for the installed package version", () => {
		const mswPackage = require("msw/package.json") as { version: string };
		const worker = readWebFile("public/mockServiceWorker.js");

		expect(worker).toContain(`const PACKAGE_VERSION = '${mswPackage.version}'`);
	});
});
