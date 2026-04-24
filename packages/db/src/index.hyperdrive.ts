import { getCloudflareContext } from "@opennextjs/cloudflare";
import { cache } from "react";
import { getDb as getDbBase } from "./index";

export { auth, organization } from "./index";

declare global {
  interface CloudflareEnv {
    HYPERDRIVE: { connectionString: string };
  }
}

/**
 * Get a Drizzle client backed by Cloudflare Hyperdrive.
 * Use in server components and API routes running on Cloudflare Workers.
 */
export const getDb = cache(() => {
  const { env } = getCloudflareContext();
  return getDbBase(env.HYPERDRIVE.connectionString);
});

/**
 * Async variant for static routes (ISR/SSG) where the Cloudflare
 * context isn't synchronously available.
 */
export const getDbAsync = cache(async () => {
  const { env } = await getCloudflareContext({ async: true });
  return getDbBase(env.HYPERDRIVE.connectionString);
});