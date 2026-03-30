import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => {
  return c.json({ name: "stackpanel-api", version: "0.0.1" });
});

app.get("/health", (c) => {
  return c.json({
    status: "ok",
    region: process.env.REGION ?? "unknown",
    timestamp: Date.now(),
  });
});

export default {
  port: Number(process.env.PORT ?? 3000),
  fetch: app.fetch,
};
