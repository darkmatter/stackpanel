import { defineConfig, devices } from "@playwright/test";

/**
 * Hosted-environment Playwright config.
 *
 * Unlike `apps/web/playwright.config.ts` (which boots a LOCAL agent + local web
 * dev server), this config drives a REMOTE deployment — production or staging —
 * so there is intentionally NO `webServer` block.
 *
 *   # read-only smoke against staging (preferred once it's healthy)
 *   SMOKE_BASE_URL=https://staging.stackpanel.com \
 *     bunx playwright test --config apps/web/e2e-hosted/playwright.hosted.config.ts
 *
 *   # read-only smoke against production (default)
 *   bunx playwright test --config apps/web/e2e-hosted/playwright.hosted.config.ts
 *
 * Smoke specs (*.smoke.spec.ts) are READ-ONLY: no login, no signup, no mutations.
 * The authenticated studio<->agent flow lives in *.studio.spec.ts and requires
 * extra env (see README.md); it is gated so it only runs when configured.
 */

const baseURL = process.env.SMOKE_BASE_URL ?? "https://stackpanel.com";

export default defineConfig({
	testDir: ".",
	fullyParallel: true,
	forbidOnly: !!process.env.CI,
	retries: process.env.CI ? 2 : 1,
	workers: process.env.CI ? 2 : 3,
	timeout: 60_000,
	expect: { timeout: 15_000 },
	reporter: [["list"]],
	outputDir: "test-results",
	use: {
		baseURL,
		trace: "retain-on-failure",
		screenshot: "only-on-failure",
		video: "off",
		// Some sandboxed/CI environments route egress through a TLS-intercepting
		// proxy whose CA the browser doesn't trust (curl succeeds, but Chromium
		// reports ERR_CERT_AUTHORITY_INVALID). Opt into ignoring cert errors there
		// via SMOKE_IGNORE_HTTPS_ERRORS=1. Leave it OFF in clean CI so a genuine
		// production certificate regression still fails the smoke.
		ignoreHTTPSErrors: process.env.SMOKE_IGNORE_HTTPS_ERRORS === "1",
	},
	projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
