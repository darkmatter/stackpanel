import { defineCloudflareConfig } from "@opennextjs/cloudflare";
import staticAssetsIncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/static-assets-incremental-cache";

export default defineCloudflareConfig({
  // Read-only prerendered cache from Worker static assets. R2 +
  // enableCacheInterception SSRs on miss, which 500s this Fumadocs
  // worker (no content/ on the isolate). Revalidation is a no-op.
  incrementalCache: staticAssetsIncrementalCache,
});
