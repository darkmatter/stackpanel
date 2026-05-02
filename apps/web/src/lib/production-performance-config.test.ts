import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = process.env.STACKPANEL_REPO_ROOT;

if (!repoRoot) {
	throw new Error("STACKPANEL_REPO_ROOT must be set for config tests");
}

const readRepoFile = (path: string) => readFileSync(join(repoRoot, path), "utf8");

describe("production performance configuration", () => {
	test("API routes do not import auth or API routers at module scope", () => {
		const authRoute = readRepoFile("apps/web/src/routes/api/auth.$.ts");
		const trpcRoute = readRepoFile("apps/web/src/routes/api/trpc.$.ts");

		expect(authRoute).not.toMatch(
			/^import\s+.*from\s+["']@stackpanel\/auth["']/m,
		);
		expect(trpcRoute).not.toMatch(
			/^import\s+.*from\s+["']@stackpanel\/auth["']/m,
		);
		expect(trpcRoute).not.toMatch(
			/^import\s+.*from\s+["']@stackpanel\/api["']/m,
		);
	});

	test("root route does not statically import devtools into production bundles", () => {
		const rootRoute = readRepoFile("apps/web/src/routes/__root.tsx");

		expect(rootRoute).not.toMatch(
			/^import\s+.*from\s+["']@tanstack\/react-query-devtools["']/m,
		);
		expect(rootRoute).not.toMatch(
			/^import\s+.*from\s+["']@tanstack\/react-router-devtools["']/m,
		);
	});

	test("web worker deploy forwards production auth URL configuration", () => {
		const deploy = readRepoFile("apps/web/alchemy.run.ts");

		expect(deploy).toContain("BETTER_AUTH_URL");
		expect(deploy).toContain("CORS_ORIGIN");
	});

	test("hashed Vite assets are immutable in browser caches", () => {
		const headers = readRepoFile("apps/web/public/_headers");

		expect(headers).toContain("/assets/*");
		expect(headers).toContain("max-age=31536000,immutable");
	});

	test("docs app declares canonical metadata base for production", () => {
		const layout = readRepoFile("apps/docs/src/app/layout.tsx");

		expect(layout).toContain("metadataBase");
		expect(layout).toContain("https://docs.stackpanel.com");
	});

	test("docs worker uses a writable R2 incremental cache", () => {
		const deploy = readRepoFile("apps/docs/alchemy.run.ts");
		const openNextConfig = readRepoFile("apps/docs/open-next.config.ts");

		expect(openNextConfig).toContain("r2-incremental-cache");
		expect(deploy).toContain("NEXT_INC_CACHE_R2_BUCKET");
		expect(deploy).toContain("bindings");
	});
});
