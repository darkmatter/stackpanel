import { createServerFn } from "@tanstack/react-start";
import { getRequestHeaders } from "@tanstack/react-start/server";

import { authMiddleware } from "@/middleware/auth";

export const getPayment = createServerFn({ method: "GET" })
	.middleware([authMiddleware])
	.handler(async () => {
		const headers = new Headers(getRequestHeaders());
		const proto = headers.get("x-forwarded-proto") ?? "http";
		const host = headers.get("x-forwarded-host") ?? headers.get("host");

		if (!host) {
			throw new Error(
				"Missing Host header; cannot build absolute URL for auth API",
			);
		}

		const baseUrl = `${proto}://${host}`;
		const url = new URL("/api/auth/customer/state", baseUrl);

		const res = await fetch(url, { headers });
		if (!res.ok) {
			const text = await res.text().catch(() => "");
			throw new Error(`Failed to fetch customer state: ${res.status} ${text}`);
		}

		const body = (await res.json()) as { data?: unknown };
		return body.data ?? null;
	});
