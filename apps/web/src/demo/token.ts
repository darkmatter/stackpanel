/**
 * Build a fake JWT for the demo agent.
 *
 * `AgentProvider` only *decodes* the JWT (it never verifies the signature),
 * so a hand-crafted token with valid base64url segments and an `exp` claim in
 * the future is enough to flip the studio into a "connected" state.
 */

function base64UrlEncode(input: string): string {
	const base64 =
		typeof window === "undefined"
			? Buffer.from(input, "utf-8").toString("base64")
			: btoa(input);
	return base64.replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function buildDemoToken(): string {
	const header = base64UrlEncode(JSON.stringify({ alg: "HS256", typ: "JWT" }));
	const payload = base64UrlEncode(
		JSON.stringify({
			agent_id: "demo-agent",
			// year 2099
			exp: 4_070_908_800,
			demo: true,
		}),
	);
	return `${header}.${payload}.demo-signature`;
}

export const DEMO_TOKEN = buildDemoToken();
