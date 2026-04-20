import { expect, test } from "@playwright/test";
import { gotoStudioApps } from "./support/studio";

test("loads app cards from the local agent", async ({ page }) => {
	await gotoStudioApps(page);

	await expect(page.getByText("docs", { exact: true }).first()).toBeVisible();
	await expect(page.getByText("stackpanel", { exact: true }).first()).toBeVisible();
	await expect(page.getByText("web", { exact: true }).first()).toBeVisible();
});
