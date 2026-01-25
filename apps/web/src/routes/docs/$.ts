/**
 * Docs Proxy Route
 *
 * Proxies requests from /docs/* to a configurable documentation server.
 * Configure the target URL via DOCS_PROXY_URL environment variable.
 *
 * Example:
 *   DOCS_PROXY_URL=http://localhost:3002
 *   Request to /docs/getting-started -> http://localhost:3002/docs/getting-started
 */
import { createFileRoute } from "@tanstack/react-router";

const DOCS_PROXY_URL = process.env.DOCS_PROXY_URL;

async function proxyHandler(request: Request): Promise<Response> {
	if (!DOCS_PROXY_URL) {
		return new Response(
			JSON.stringify({
				error: "DOCS_PROXY_URL environment variable is not configured",
			}),
			{
				status: 503,
				headers: { "Content-Type": "application/json" },
			},
		);
	}

	try {
		// Get the path after /docs
		const url = new URL(request.url);
		const path = url.pathname; // e.g., /docs/getting-started

		// Build the target URL
		const targetUrl = new URL(path, DOCS_PROXY_URL);
		targetUrl.search = url.search; // Preserve query params

		// Clone headers, removing host-specific ones
		const headers = new Headers(request.headers);
		headers.delete("host");
		headers.delete("connection");

		// Make the proxy request
		const proxyResponse = await fetch(targetUrl.toString(), {
			method: request.method,
			headers,
			body:
				request.method !== "GET" && request.method !== "HEAD"
					? await request.text()
					: undefined,
			redirect: "manual", // Handle redirects manually to rewrite them
		});

		// Clone response headers
		const responseHeaders = new Headers(proxyResponse.headers);

		// Rewrite redirect locations to go through the proxy
		const location = responseHeaders.get("location");
		if (location) {
			try {
				const locationUrl = new URL(location, DOCS_PROXY_URL);
				// If redirect is to the docs server, rewrite it to go through our proxy
				if (locationUrl.origin === new URL(DOCS_PROXY_URL).origin) {
					responseHeaders.set("location", locationUrl.pathname + locationUrl.search);
				}
			} catch {
				// Invalid URL, leave as-is
			}
		}

		// Remove headers that shouldn't be forwarded
		responseHeaders.delete("transfer-encoding");
		responseHeaders.delete("content-encoding"); // Let the browser handle compression

		return new Response(proxyResponse.body, {
			status: proxyResponse.status,
			statusText: proxyResponse.statusText,
			headers: responseHeaders,
		});
	} catch (error) {
		console.error("Docs proxy error:", error);
		return new Response(
			JSON.stringify({
				error: "Failed to proxy request to docs server",
				details: error instanceof Error ? error.message : String(error),
			}),
			{
				status: 502,
				headers: { "Content-Type": "application/json" },
			},
		);
	}
}

export const Route = createFileRoute("/docs/$")({
	server: {
		handlers: {
			GET: ({ request }) => proxyHandler(request),
			POST: ({ request }) => proxyHandler(request),
			PUT: ({ request }) => proxyHandler(request),
			PATCH: ({ request }) => proxyHandler(request),
			DELETE: ({ request }) => proxyHandler(request),
			HEAD: ({ request }) => proxyHandler(request),
			OPTIONS: ({ request }) => proxyHandler(request),
		},
	},
});
