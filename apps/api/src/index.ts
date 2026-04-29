import { auth } from "@stackpanel/auth";
import { appRouter, createTRPCContext } from "@stackpanel/api";
import { fetchRequestHandler } from "@trpc/server/adapters/fetch";
import { Hono } from "hono";
import { cors } from "hono/cors";

/**
 * Cloud API for stackpanel — mounted at api.stackpanel.com.
 *
 * Hosts Better-Auth (email/password + Polar payments + webhooks),
 * gated tRPC procedures for hosted alchemy state, and (future) marketplace
 * catalog endpoints. Runs on Fly (Node/Bun), not Cloudflare Workers —
 * needs real Node APIs for AWS KMS + AES-GCM envelope encryption.
 */

const app = new Hono();

// Origins allowed to call this API with credentials. The studio lives on
// local.stackpanel.com (production) or localhost during dev, so both need
// to be in the allowlist — `credentials: true` requires exact-match origins.
const allowedOrigins = (process.env.CORS_ALLOWED_ORIGINS ?? "")
	.split(",")
	.map((s: string) => s.trim())
	.filter(Boolean);

const defaultOrigins = [
	"http://localhost:3000",
	"http://localhost:5775",
	"https://local.stackpanel.com",
	"https://stackpanel.com",
];

const origins = allowedOrigins.length > 0 ? allowedOrigins : defaultOrigins;

app.use(
	"*",
	cors({
		origin: origins,
		credentials: true,
		allowMethods: ["GET", "POST", "OPTIONS"],
		allowHeaders: ["Content-Type", "Authorization", "Cookie"],
		exposeHeaders: ["Set-Cookie"],
	}),
);

app.get("/", (c) =>
	c.json({ name: "stackpanel-api", version: "0.0.1" }),
);

app.get("/health", (c) =>
	c.json({
		status: "ok",
		region: process.env.FLY_REGION ?? process.env.REGION ?? "unknown",
		timestamp: Date.now(),
	}),
);

// Better-Auth handler — covers /api/auth/* (sign-in, sign-up, session,
// social OAuth, Polar checkout/portal, and webhook mount). All routes
// emitted by the plugin tree are handled here.
app.on(["POST", "GET"], "/api/auth/*", (c) => auth.handler(c.req.raw));

// tRPC handler. Studio talks to this via @trpc/client httpBatchStreamLink.
app.all("/trpc/*", (c) =>
	fetchRequestHandler({
		endpoint: "/trpc",
		req: c.req.raw,
		router: appRouter,
		createContext: () =>
			createTRPCContext({ headers: c.req.raw.headers, auth }),
	}),
);

export default {
	port: Number(process.env.PORT ?? 3000),
	fetch: app.fetch,
};
