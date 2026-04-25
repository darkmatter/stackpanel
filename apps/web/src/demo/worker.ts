/**
 * Browser-side MSW worker setup.
 *
 * Lazily imports `msw/browser` so the demo bundle is only pulled in on the
 * `/demo` route. `start()` is idempotent and resolves once the service worker
 * is intercepting requests.
 */

import { demoHandlers } from "./handlers";

type SetupWorker = Awaited<ReturnType<typeof loadWorker>>;

let workerPromise: Promise<SetupWorker> | null = null;

async function loadWorker() {
	const { setupWorker } = await import("msw/browser");
	return setupWorker(...demoHandlers);
}

export async function startDemoWorker(): Promise<void> {
	if (typeof window === "undefined") return;
	if (!workerPromise) {
		workerPromise = loadWorker();
	}
	const worker = await workerPromise;
	await worker.start({
		// Don't warn about real requests the studio fires (auth, fonts, etc.)
		onUnhandledRequest: "bypass",
		serviceWorker: {
			url: "/mockServiceWorker.js",
		},
	});
}

export async function stopDemoWorker(): Promise<void> {
	if (!workerPromise) return;
	const worker = await workerPromise;
	worker.stop();
	workerPromise = null;
}
