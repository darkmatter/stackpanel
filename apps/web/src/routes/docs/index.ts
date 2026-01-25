/**
 * Docs Proxy Route - Index
 *
 * Handles /docs (without trailing path) by proxying to the docs server.
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
		)
	}

	try {
		const url = new URL(request.url);
		const targetUrl = new URL("/docs", DOCS_PROXY_URL);
		targetUrl.search = url.search;

		const headers = new Headers(request.headers);
		headers.delete("host");
		headers.delete("connection");

		const proxyResponse = await fetch(targetUrl.toString(), {
			method: request.method,
			headers,
			body:
				request.method !== "GET" && request.method !== "HEAD"
					? await request.text()
					: undefined,
			redirect: "manual",
		})

		const responseHeaders = new Headers(proxyResponse.headers);

		const location = responseHeaders.get("location");
		if (location) {
			try {
				const locationUrl = new URL(location, DOCS_PROXY_URL);
				if (locationUrl.origin === new URL(DOCS_PROXY_URL).origin) {
					responseHeaders.set("location", locationUrl.pathname + locationUrl.search);
				}
			} catch {
				// Invalid URL, leave as-is
			}
		}

		responseHeaders.delete("transfer-encoding");
		responseHeaders.delete("content-encoding");

		return new Response(proxyResponse.body, {
			status: proxyResponse.status,
			statusText: proxyResponse.statusText,
			headers: responseHeaders,
		})
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
		)
	}
}

export const Route = createFileRoute("/docs/")({
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
