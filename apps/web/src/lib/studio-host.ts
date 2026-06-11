/**
 * Hostnames for the hosted studio ("desktop") product — the local.stackpanel.*
 * bridge that talks to the user's agent at localhost:9876.
 *
 * Marketing lives on stackpanel.com; studio hosts should land on auth, not `/`.
 */

const STUDIO_HOST_PATTERNS = [
	/^local\.stackpanel\.(com|dev)$/,
	/^local\.[^.]+\.stackpanel\.com$/,
] as const;

export function isStudioHost(hostname: string): boolean {
	const host = hostname.split(":")[0]?.toLowerCase() ?? "";
	if (!host) return false;
	if (host === "localhost" || host === "127.0.0.1") return true;
	return STUDIO_HOST_PATTERNS.some((pattern) => pattern.test(host));
}

export async function resolveRequestHostname(): Promise<string | null> {
	if (typeof window !== "undefined") {
		return window.location.hostname;
	}

	const { getRequestHeaders } = await import("@tanstack/react-start/server");
	const headers = getRequestHeaders();
	return (
		headers.get("x-forwarded-host")?.split(":")[0] ??
		headers.get("host")?.split(":")[0] ??
		null
	);
}
