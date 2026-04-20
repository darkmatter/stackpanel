import { expect, test } from "@playwright/test";
import { gotoStudioApps } from "./support/studio";

test("shows configured app.env variables for the web app", async ({ page }) => {
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

	await expect(webCard.getByText("PORT", { exact: true })).toBeVisible();
	await expect(webCard.getByText("HOSTNAME", { exact: true })).toBeVisible();
});
