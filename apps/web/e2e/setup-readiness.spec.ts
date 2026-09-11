import { createHash, randomBytes } from "node:crypto";
import { mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { expect, test } from "@playwright/test";
import {
  PLAYWRIGHT_AGENT_PORT,
  PLAYWRIGHT_BASE_URL,
  PLAYWRIGHT_WEB_HOST,
  REPO_ROOT,
} from "./support/constants";

test.skip(
  process.env.STACKPANEL_E2E_UNPAIRED !== "1",
  "Run with STACKPANEL_E2E_UNPAIRED=1 to exercise actual browser pairing",
);

test("pairs, loads the requested repository, acknowledges readiness, and invalidates disconnects", async ({
  page,
  request,
}) => {
  const root = realpathSync(REPO_ROOT);
  const endpoint = `http://${PLAYWRIGHT_WEB_HOST}:${PLAYWRIGHT_AGENT_PORT}`;
  const health = await (await request.get(`${endpoint}/health`)).json();
  const projectId = createHash("sha256").update(root).digest("hex").slice(0, 8);
  const id = randomBytes(32).toString("hex");
  const userConfig = process.env.STACKPANEL_USER_CONFIG;
  if (!userConfig) throw new Error("Set STACKPANEL_USER_CONFIG to an isolated test config");
  const directory = join(dirname(userConfig), "setup-sessions");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const path = join(directory, `${id}.json`);
  writeFileSync(
    path,
    JSON.stringify({
      id,
      root,
      projectId,
      agentId: health.agent_id,
      endpoint,
      origin: PLAYWRIGHT_BASE_URL,
      expires: new Date(Date.now() + 600_000).toISOString(),
      requireBrowser: true,
    }),
    { mode: 0o600 },
  );
  const readSession = () => JSON.parse(readFileSync(path, "utf8"));
  const query = new URLSearchParams({ setup: id, project: projectId, agent: endpoint });
  await page.goto(`/studio?${query}`);
  await expect(page.getByRole("button", { name: "Connect to Agent", exact: true })).toBeEnabled();
  const popupPromise = page.waitForEvent("popup");
  await page.getByRole("button", { name: "Connect to Agent", exact: true }).click();
  const popup = await popupPromise;
  await popup.getByRole("button", { name: "Pair", exact: true }).click();
  await expect(page.getByTestId("setup-readiness")).toContainText("Studio ready", {
    timeout: 120_000,
  });
  await expect.poll(() => readSession().readyAt).not.toBe("0001-01-01T00:00:00Z");
  expect(readSession().connection).toBeTruthy();
  await page.goto("about:blank");
  await expect.poll(() => readSession().connection ?? "").toBe("");
  // The final bookmark keeps the agent endpoint but no expiring setup receipt.
  await page.goto(`/studio?${new URLSearchParams({ project: projectId, agent: endpoint })}`);
  await expect(
    page.getByRole("button", { name: "Connect to Agent", exact: true }),
  ).not.toBeVisible();
  await expect(page.getByTestId("setup-readiness")).toHaveCount(0);
});

test("reports a blocked pairing popup", async ({ page }) => {
  await page.goto("/studio");
  await expect(page.getByRole("button", { name: "Connect to Agent", exact: true })).toBeEnabled();
  await page.evaluate(() => {
    window.open = () => null;
  });
  await page.getByRole("button", { name: "Connect to Agent", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("blocked the pairing popup");
});
