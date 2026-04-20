import { expect, type Page } from "@playwright/test";

export async function gotoStudioApps(page: Page) {
	await page.goto("/studio/apps");
	await expect(page).toHaveURL(/\/studio\/apps$/);
}
