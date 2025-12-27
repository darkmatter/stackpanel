/// <reference path="../../../.sst/platform/config.d.ts" />

import { getDomain } from "../config";

interface DocsOptions {
  isProd: boolean;
}

/**
 * Docs: Fumadocs (Next.js Static Export) on Cloudflare
 */
export function createDocs({ isProd }: DocsOptions) {
  return new sst.cloudflare.StaticSite("Docs", {
    path: "apps/docs",
    build: {
      command: "bun run build",
      output: "out",
    },
    domain: getDomain("docs", isProd),
  });
}
