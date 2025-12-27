/// <reference path="../../../.sst/platform/config.d.ts" />

import { config, getDomain, getEnvironment } from "../config";
import type { Secrets } from "../secrets";

interface WebAppOptions {
	secrets: Secrets;
	isProd: boolean;
}

/**
 * Web App: TanStack Start on Cloudflare Workers
 *
 * Workers are globally distributed - no load balancer needed!
 */
export function createWebApp({ secrets, isProd }: WebAppOptions) {
	return new sst.cloudflare.Worker("Web", {
		handler: "apps/web/.output/server/index.mjs",
		url: true,
		domain: getDomain("web", isProd),
		link: Object.values(secrets),
		environment: getEnvironment(isProd),
	});
}
