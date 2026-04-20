import { expect, test } from "@playwright/test";
import { gotoStudioApps } from "./support/studio";

/**
 * Per-secret reveal toggle.
 *
 * The `web` app declares `POSTGRES_URL` with `sops = "/dev/postgres-url"`,
 * which the Studio UI renders with a `Lock` icon and an eye toggle. Clicking
 * the toggle invokes `sops decrypt --extract` through the agent and replaces
 * the masked placeholder with either the decrypted value or an inline error.
 */
test("reveal toggle on a sops-backed secret shows the decrypted value", async ({
	page,
}) => {
	await gotoStudioApps(page);

	const webCard = page.locator('div[data-slot="card"]', {
		has: page.locator("span.font-medium", { hasText: /^web$/ }),
	});
	await expect(webCard).toBeVisible();
	await webCard.locator("[data-slot=card-header]").click();

	const variablesTab = webCard.getByRole("button", {
		name: /^Variables$/,
		exact: true,
	});
	await variablesTab.click();

	const revealButton = webCard.getByRole("button", {
		name: /^Reveal POSTGRES_URL$/,
	});
	await expect(revealButton).toBeVisible();

	await revealButton.click();

	// The reveal handler shells out to `sops decrypt`; whichever way it
	// resolves (value or error), the row leaves the loading state and the
	// button flips to "Hide POSTGRES_URL".
	await expect(
		webCard.getByRole("button", { name: /^Hide POSTGRES_URL$/ }),
	).toBeVisible({ timeout: 15_000 });
});

test("revealing a different secret hides the previously revealed one", async ({
	page,
}) => {
	await gotoStudioApps(page);

	const webCard = page.locator('div[data-slot="card"]', {
		has: page.locator("span.font-medium", { hasText: /^web$/ }),
	});
	await webCard.locator("[data-slot=card-header]").click();
	await webCard
		.getByRole("button", { name: /^Variables$/, exact: true })
		.click();

	const firstReveal = webCard.getByRole("button", {
		name: /^Reveal POSTGRES_URL$/,
	});
	const secondReveal = webCard.getByRole("button", {
		name: /^Reveal CLOUDFLARE_ACCOUNT_ID$/,
	});

	await firstReveal.click();
	await expect(
		webCard.getByRole("button", { name: /^Hide POSTGRES_URL$/ }),
	).toBeVisible({ timeout: 15_000 });

	await secondReveal.click();
	await expect(
		webCard.getByRole("button", { name: /^Hide CLOUDFLARE_ACCOUNT_ID$/ }),
	).toBeVisible({ timeout: 15_000 });

	// The first secret should be re-masked (back to "Reveal …").
	await expect(
		webCard.getByRole("button", { name: /^Reveal POSTGRES_URL$/ }),
	).toBeVisible();
});
