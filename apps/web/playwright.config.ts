import { defineConfig, devices } from "@playwright/test";
import { getAgentToken } from "./e2e/support/agent-auth";
import {
	PLAYWRIGHT_AGENT_PORT,
	PLAYWRIGHT_BASE_URL,
	PLAYWRIGHT_PAIRING_SECRET,
	PLAYWRIGHT_WEB_HOST,
	PLAYWRIGHT_WEB_PORT,
	REPO_ROOT,
	STACKPANEL_GO_DIR,
	WEB_APP_DIR,
} from "./e2e/support/constants";

const playwrightAgentToken = getAgentToken(PLAYWRIGHT_BASE_URL);

export default defineConfig({
	testDir: "./e2e",
	testIgnore: ["**/support/**"],
	fullyParallel: false,
	workers: 1,
	forbidOnly: !!process.env.CI,
	retries: process.env.CI ? 1 : 0,
	timeout: 90_000,
	expect: {
		timeout: 10_000,
	},
	reporter: "list",
	use: {
		baseURL: PLAYWRIGHT_BASE_URL,
		trace: "retain-on-failure",
		screenshot: "only-on-failure",
		video: "retain-on-failure",
	},
	projects: [
		{
			name: "chromium",
			use: {
				...devices["Desktop Chrome"],
			},
		},
	],
	webServer: [
		{
			name: "agent",
			command: `go run . agent --port ${PLAYWRIGHT_AGENT_PORT} --project-root "${REPO_ROOT}"`,
			cwd: STACKPANEL_GO_DIR,
			env: {
				...process.env,
				STACKPANEL_TEST_PAIRING_TOKEN: PLAYWRIGHT_PAIRING_SECRET,
			},
			url: `http://${PLAYWRIGHT_WEB_HOST}:${PLAYWRIGHT_AGENT_PORT}/health`,
			reuseExistingServer: false,
			stdout: "pipe",
			stderr: "pipe",
			timeout: 180_000,
			gracefulShutdown: {
				signal: "SIGTERM",
				timeout: 10_000,
			},
		},
		{
			name: "web",
			command: `bun run dev -- --host ${PLAYWRIGHT_WEB_HOST} --port ${PLAYWRIGHT_WEB_PORT}`,
			cwd: WEB_APP_DIR,
			env: {
				...process.env,
				VITE_STACKPANEL_AGENT_HOST: PLAYWRIGHT_WEB_HOST,
				VITE_STACKPANEL_AGENT_PORT: String(PLAYWRIGHT_AGENT_PORT),
				VITE_STACKPANEL_AGENT_TOKEN: playwrightAgentToken,
			},
			url: `${PLAYWRIGHT_BASE_URL}/studio/apps`,
			reuseExistingServer: false,
			stdout: "pipe",
			stderr: "pipe",
			timeout: 180_000,
			gracefulShutdown: {
				signal: "SIGTERM",
				timeout: 10_000,
			},
		},
	],
});
