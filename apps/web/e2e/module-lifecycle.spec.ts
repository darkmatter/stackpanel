import { expect, test } from "@playwright/test";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { serveModuleProject } from "./support/module-project";

test("installs a registry version, reviews enablement, edits settings and runs its Studio panels", async ({
  page,
}) => {
  const project = await serveModuleProject(page);
  await page.goto("/studio/modules");
  await expect(page.getByRole("button", { name: "View Details" })).toBeVisible();
  await page.getByRole("textbox", { name: "Search modules" }).fill("no-matching-module");
  await expect(page.getByText("No matching modules", { exact: true })).toBeVisible();
  await page.getByRole("textbox", { name: "Search modules" }).fill("status");
  await page.getByRole("button", { name: "View Details" }).click();
  await expect(page.getByRole("heading", { name: "Status guide" })).toBeVisible();
  await page.getByLabel("Version", { exact: true }).selectOption("1");
  await page.getByRole("textbox", { name: "Git ref" }).fill("review");
  await page.getByRole("button", { name: "Install", exact: true }).click();
  const preview = page.getByRole("dialog", { name: "Enable module?" });
  await expect(preview).toContainText("status.json");
  await expect(preview).toContainText("Use existing status file");
  expect(project.searches).toContain("status");
  expect(project).toMatchObject({ installed: true, enabled: false, version: "1", ref: "review" });
  const decision = preview.getByRole("combobox", { name: "Use existing status file" });
  await expect(decision).toHaveValue("skip");
  await decision.selectOption("true");
  await expect(preview.getByText("adopted-status.json", { exact: true })).toBeVisible();
  await preview.getByRole("button", { name: "Enable", exact: true }).click();
  await expect(page.getByText("Status board enabled", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Configure module" }).click();
  await page.getByRole("tab", { name: "Config", exact: true }).click();
  await page.getByRole("textbox", { name: "Greeting" }).fill("Good morning");
  await page.getByRole("button", { name: "Save Changes" }).click();
  await expect(page.getByText("Greeting saved", { exact: true })).toBeVisible();
  await page.getByRole("tab", { name: "Overview" }).click();
  await page.getByRole("button", { name: "Inspect greeting" }).click();
  const runner = page.getByRole("dialog", { name: "Inspect greeting" });
  await expect(runner.getByRole("log")).toContainText("greeting=Good morning");
  await expect(runner.getByRole("log")).toContainText("inspection complete");
  await expect(runner.getByRole("status")).toHaveText("Exit code 0");
  await runner.getByRole("button", { name: "Close" }).click();
  const picker = page.getByRole("combobox", { name: "Inspect app" });
  await picker.selectOption("web");
  expect(project.statusReads).toEqual([]);
  await page.getByRole("button", { name: "Load once" }).click();
  await expect(page.locator("sp-status-view pre")).toContainText("web: healthy");
  expect(project.statusReads).toEqual(["web"]);
  await expect(page.locator("iframe[sandbox]")).toHaveCount(0);
  await page.getByRole("button", { name: "Deny", exact: true }).click();
  await expect(page.locator("iframe[sandbox]")).toHaveCount(0);
  await page.getByRole("button", { name: "Review panel" }).click();
  await page.getByRole("button", { name: "Open panel once" }).click();
  const iframe = page.locator("iframe[sandbox]");
  await expect(iframe).toHaveAttribute("sandbox", "allow-scripts");
  await expect(iframe).toHaveAttribute("referrerpolicy", "no-referrer");
  const frame = iframe.contentFrame();
  const readGreeting = frame.getByRole("button", { name: "Read greeting" });
  await expect(readGreeting).toBeVisible();
  const refreshPath = `/${ModuleService.typeName}/${ModuleService.method.openModuleUI.name}`;
  const [configRead] = await Promise.all([
    page.waitForRequest(
      (req) => req.method() === "POST" && new URL(req.url()).pathname === refreshPath,
    ),
    readGreeting.click(),
  ]);
  expect(await configRead.headerValue("x-stackpanel-ui-grant")).toBe("fixture-binding");
  await expect(frame.getByText("status-board/status: Good morning")).toBeVisible();
  const readService = frame.getByRole("button", { name: "Read local service" });
  await readService.click();
  const deny = page.getByRole("button", { name: "Deny request" });
  await expect(deny).toBeVisible();
  expect(project.proxyCalls).toBe(0);
  await deny.click();
  await expect(frame.getByText(/denied|not (approved|allowed)/i)).toBeVisible();
  expect(project.proxyCalls).toBe(0);
  await readService.click();
  await page.getByRole("button", { name: "Allow once" }).click();
  await expect(frame.getByText("Local service is ready")).toBeVisible();
  expect(project.proxyCalls).toBe(1);
  await frame.getByRole("button", { name: "Try changing greeting" }).click();
  await expect(frame.getByText(/permission not granted/i)).toBeVisible();
  expect(project.patches).toEqual([{ greeting: "Good morning" }]);
  expect(project.actions).toEqual(["inspect"]);
  await page.getByRole("button", { name: "Stop panel" }).click();
  await expect(iframe).toHaveCount(0);
  await page.goto("/studio/panels?module=status-board");
  await expect(page.getByRole("heading", { name: "Status board", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open panel once" })).toBeVisible();
  await expect(page.locator("iframe[sandbox]")).toHaveCount(0);
});
