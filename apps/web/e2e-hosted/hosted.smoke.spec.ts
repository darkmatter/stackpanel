import { test, expect, type Page } from "@playwright/test";

/**
 * Read-only hosted smoke. NO authentication, NO mutations — safe against prod or staging.
 *
 * The deployed studio is a client-rendered SPA, so this is intentionally
 * selector-light: the strongest, most durable signal is "no uncaught page
 * errors", which catches white-screen / hydration-crash regressions that a
 * status-code check alone would miss.
 */

function collectPageErrors(page: Page): string[] {
	const errors: string[] = [];
	page.on("pageerror", (err) => errors.push(err.message ?? String(err)));
	return errors;
}

test.describe("hosted smoke (read-only, unauthenticated)", () => {
	test("landing renders without uncaught page errors", async ({ page }) => {
		const errors = collectPageErrors(page);
		const res = await page.goto("/", { waitUntil: "domcontentloaded" });
		expect(res?.status() ?? 0, "GET / status").toBeLessThan(400);
		await page.waitForLoadState("load");
		const text = (await page.locator("body").innerText().catch(() => "")).trim();
		expect(text.length, "landing shows visible text").toBeGreaterThan(0);
		expect(errors, `uncaught errors on /:\n${errors.join("\n")}`).toEqual([]);
	});

	test("/dashboard gates unauthenticated visitors to /login", async ({ page }) => {
		await page.goto("/dashboard", { waitUntil: "domcontentloaded" });
		await page.waitForURL(/\/login/, { timeout: 15_000 }).catch(() => {});
		expect(page.url(), "expected redirect to /login").toMatch(/\/login/);
	});

	test("/login presents a sign-in affordance", async ({ page }) => {
		const res = await page.goto("/login", { waitUntil: "domcontentloaded" });
		expect(res?.status() ?? 0, "GET /login status").toBeLessThan(400);
		const emailField = page.locator('input[type="email"], input[name="email"]');
		const signInControl = page
			.getByRole("button", { name: /sign ?in|log ?in|continue|sign ?up/i })
			.or(page.getByText(/sign ?in|log ?in/i));
		await expect(
			emailField.or(signInControl).first(),
			"a login form or sign-in control is visible",
		).toBeVisible({ timeout: 15_000 });
	});

	test("/studio responds without a server error or crash", async ({ page }) => {
		const errors = collectPageErrors(page);
		const res = await page.goto("/studio", { waitUntil: "domcontentloaded" });
		expect(res?.status() ?? 0, "GET /studio status (no 5xx)").toBeLessThan(500);
		await page.waitForLoadState("load");
		expect(errors, `uncaught errors on /studio:\n${errors.join("\n")}`).toEqual([]);
		// Observed 2026-06: /studio returns 200 with no server-side redirect for
		// unauthenticated users (client-gated), unlike /dashboard. Recorded for the audit.
		// eslint-disable-next-line no-console
		console.log(`[hosted-smoke] /studio settled at: ${page.url()}`);
	});
});
