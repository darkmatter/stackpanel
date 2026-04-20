import { fileURLToPath } from "node:url";

export const PLAYWRIGHT_WEB_HOST = "127.0.0.1";
export const PLAYWRIGHT_WEB_PORT = 3101;
export const PLAYWRIGHT_AGENT_PORT = 19876;
export const PLAYWRIGHT_PAIRING_SECRET = "stackpanel-playwright-e2e";

export const PLAYWRIGHT_BASE_URL = `http://${PLAYWRIGHT_WEB_HOST}:${PLAYWRIGHT_WEB_PORT}`;
export const WEB_APP_DIR = fileURLToPath(new URL("../..", import.meta.url));
export const REPO_ROOT = fileURLToPath(new URL("../../../../", import.meta.url));
export const STACKPANEL_GO_DIR = fileURLToPath(
	new URL("../../../../apps/stackpanel-go/", import.meta.url),
);
