import { defineCloudflareConfig } from "@opennextjs/cloudflare";
import r2IncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/r2-incremental-cache";

export default defineCloudflareConfig({
  // See https://opennext.js.org/cloudflare/caching for more details
  incrementalCache: r2IncrementalCache,
  enableCacheInterception: true,
});
