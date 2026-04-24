import { auth } from "@stackpanel/auth";
import { appRouter, createTRPCContext } from "@stackpanel/api";
import { fetchRequestHandler } from "@trpc/server/adapters/fetch";
import { Hono } from "hono";
import { cors } from "hono/cors";

/**
 * Cloud API for stackpanel — mounted at api.stackpanel.com.
 *
 * Runs as a Cloudflare Worker. Hosts Better-Auth (email/password + Polar
 * payments + webhooks), gated tRPC procedures for hosted alchemy state,
 * and (future) marketplace catalog endpoints.
 *
 * Encryption uses Web Crypto + aws4fetch so everything works in the Workers
 * runtime without Node-specific SDKs.
 */

type Env = {
	CORS_ALLOWED_ORIGINS?: string;
	CORS_ORIGIN?: string;
	BETTER_AUTH_URL?: string;
	BETTER_AUTH_SECRET?: string;
	DATABASE_URL?: string;
	AWS_ACCESS_KEY_ID?: string;
	AWS_SECRET_ACCESS_KEY?: string;
	AWS_REGION?: string;
	STACKPANEL_KMS_ALIAS?: string;
	POLAR_ACCESS_TOKEN?: string;
	POLAR_WEBHOOK_SECRET?: string;
	POLAR_SUCCESS_URL?: string;
	POLAR_PRO_PRODUCT_ID_PRODUCTION?: string;
	POLAR_FREE_PRODUCT_ID_PRODUCTION?: string;
};

const defaultOrigins = [
	"http://localhost:3000",
	"http://localhost:5775",
	"https://local.stackpanel.com",
	"https://stackpanel.com",
];

const app = new Hono<{ Bindings: Env }>();

app.use("*", async (c, next) => {
	// Hand the Worker's bindings to library code that reads process.env style
	// names (encryption helpers, Better-Auth, Polar). A per-request assignment
	// is fine: Workers isolate requests, no cross-request leakage.
	(globalThis as { __env?: Record<string, string | undefined> }).__env = {
		...c.env,
	};
	return cors({
		origin: (c.env.CORS_ALLOWED_ORIGINS?.split(",").map((s) => s.trim()).filter(Boolean))
			?? defaultOrigins,
		credentials: true,
		allowMethods: ["GET", "POST", "OPTIONS"],
		allowHeaders: ["Content-Type", "Authorization", "Cookie"],
		exposeHeaders: ["Set-Cookie"],
	})(c, next);
});

app.get("/", (c) => c.json({ name: "stackpanel-api", version: "0.0.1" }));

app.get("/health", (c) =>
	c.json({
		status: "ok",
		region: ((c.req.raw as unknown as { cf?: { colo?: string } }).cf?.colo) ?? "unknown",
		timestamp: Date.now(),
	}),
);

// Better-Auth handles sign-in, sign-up, session, Polar checkout/portal,
// and the /polar/webhooks mount. Every route emitted by the plugin tree
// flows through this single handler.
app.on(["POST", "GET"], "/api/auth/*", (c) => auth.handler(c.req.raw));

// tRPC handler — studio talks here via @trpc/client httpBatchStreamLink.
app.all("/trpc/*", (c) =>
	fetchRequestHandler({
		endpoint: "/trpc",
		req: c.req.raw,
		router: appRouter,
		createContext: () => createTRPCContext({ headers: c.req.raw.headers, auth }),
	}),
);

export default app;
