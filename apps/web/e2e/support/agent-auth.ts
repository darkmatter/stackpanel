import { execFileSync } from "node:child_process";
import {
	PLAYWRIGHT_BASE_URL,
	PLAYWRIGHT_PAIRING_SECRET,
	STACKPANEL_GO_DIR,
} from "./constants";

interface TestTokenPayload {
	token: string;
	agent_id: string;
	origin: string;
}

const tokenCache = new Map<string, string>();

export function getAgentToken(origin = PLAYWRIGHT_BASE_URL): string {
	const cached = tokenCache.get(origin);
	if (cached) {
		return cached;
	}

	const stdout = execFileSync(
		"go",
		[
			"run",
			".",
			"agent",
			"test-token",
			"--origin",
			origin,
			"--json",
		],
		{
			cwd: STACKPANEL_GO_DIR,
			encoding: "utf8",
			env: {
				...process.env,
				STACKPANEL_TEST_PAIRING_TOKEN: PLAYWRIGHT_PAIRING_SECRET,
			},
		},
	);

	const payload = JSON.parse(stdout) as TestTokenPayload;
	if (!payload.token) {
		throw new Error("Failed to generate Playwright agent token");
	}

	tokenCache.set(origin, payload.token);
	return payload.token;
}
