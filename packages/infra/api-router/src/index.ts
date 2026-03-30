import { Hono } from "hono";

// Countries in the Americas region — route to US-West origin
const AMERICAS = new Set([
  "US",
  "CA",
  "MX",
  "BR",
  "AR",
  "CL",
  "CO",
  "PE",
  "VE",
  "EC",
  "BO",
  "PY",
  "UY",
  "CR",
  "PA",
  "DO",
  "GT",
  "HN",
  "SV",
  "NI",
  "CU",
  "HT",
  "JM",
  "TT",
  "PR",
]);

type Env = {
  API_ORIGIN_USW: string; // OVH US-West  e.g. http://15.204.104.4
  API_ORIGIN_HEL: string; // Hetzner Helsinki
};

const app = new Hono<{ Bindings: Env }>();

// Health / info root — useful for smoke-testing the router itself
app.get("/", (c) => {
  const country = c.req.header("CF-IPCountry") ?? "XX";
  return c.json({ router: true, region: country });
});

// Catch-all proxy — forward every other request to the appropriate origin
app.all("*", async (c) => {
  const country = c.req.header("CF-IPCountry") ?? "XX";
  const origin = AMERICAS.has(country) ? c.env.API_ORIGIN_USW : c.env.API_ORIGIN_HEL;

  // Build the upstream URL: replace the worker host with the target origin
  const url = new URL(c.req.url);
  const upstream = new URL(url.pathname + url.search, origin);

  // Clone request headers and strip Cloudflare-specific ones that should not
  // be forwarded (Host will be set automatically by fetch).
  const headers = new Headers(c.req.raw.headers);
  headers.delete("Host");

  // Attach the resolved country so the origin can use it without re-inspection
  headers.set("X-Router-Country", country);

  const response = await fetch(upstream.toString(), {
    method: c.req.method,
    headers,
    body: ["GET", "HEAD"].includes(c.req.method) ? undefined : c.req.raw.body,
    // Cloudflare Workers fetch does not follow redirects by default — keep it explicit
    redirect: "follow",
  });

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
});

export default app;
