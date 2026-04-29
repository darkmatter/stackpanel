"use client";

import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useEffect,
	useMemo,
	useState,
} from "react";
import { DEMO_HOST, DEMO_PORT } from "@/demo/fixture";
import { DEMO_TOKEN } from "@/demo/token";
import { startDemoWorker, stopDemoWorker } from "@/demo/worker";

/**
 * Why this provider exists
 * ------------------------
 *
 * Studio normally points at the local agent on `localhost:9876`. The demo
 * experience swaps that out for an MSW-backed virtual agent on
 * `${DEMO_HOST}:${DEMO_PORT}` so a marketing visitor can drive the *real*
 * Studio UI against deterministic fixture data — no install required.
 *
 * The endpoint lives at the React root (above `AgentProvider` and
 * `AgentSSEProvider`) so a landing-page CTA can flip the studio into demo
 * mode *before* the user navigates to `/studio`. Selection is persisted to
 * `localStorage` so a refresh keeps the user in the demo.
 *
 * Booting the MSW worker is async; we expose `bootingDemo` so consumers can
 * render a brief loading state while the service worker activates and
 * intercepts the first request.
 */

const STORAGE_KEY = "stackpanel.agent.endpoint";

export type AgentEndpointKind = "local" | "demo";

export interface AgentEndpoint {
	kind: AgentEndpointKind;
	host: string;
	port: number;
	/** Token to inject into AgentProvider; null means "use stored pairing token" */
	token: string | null;
}

interface LocalEndpointConfig {
	host: string;
	port: number;
	token?: string | null;
}

interface AgentEndpointContextValue {
	endpoint: AgentEndpoint;
	isDemo: boolean;
	bootingDemo: boolean;
	useDemo: () => Promise<void>;
	useLocal: () => void;
}

const AgentEndpointContext = createContext<AgentEndpointContextValue | null>(
	null,
);

function makeLocalEndpoint(config: LocalEndpointConfig): AgentEndpoint {
	return {
		kind: "local",
		host: config.host,
		port: config.port,
		token: config.token ?? null,
	};
}

const DEMO_ENDPOINT: AgentEndpoint = {
	kind: "demo",
	host: DEMO_HOST,
	port: DEMO_PORT,
	token: DEMO_TOKEN,
};

interface AgentEndpointProviderProps {
	children: ReactNode;
	/** Local agent config — when omitted, derived from `VITE_STACKPANEL_AGENT_*` env */
	local?: LocalEndpointConfig;
}

function getLocalConfigFromEnv(): LocalEndpointConfig {
	const host = import.meta.env.VITE_STACKPANEL_AGENT_HOST || "localhost";
	const parsedPort = Number.parseInt(
		import.meta.env.VITE_STACKPANEL_AGENT_PORT || "",
		10,
	);
	const token = import.meta.env.VITE_STACKPANEL_AGENT_TOKEN || null;
	return {
		host,
		port: Number.isFinite(parsedPort) ? parsedPort : 9876,
		token,
	};
}

export function AgentEndpointProvider({
	children,
	local,
}: AgentEndpointProviderProps) {
	const localEndpoint = useMemo(
		() => makeLocalEndpoint(local ?? getLocalConfigFromEnv()),
		[local],
	);

	// Initialise synchronously so a refresh inside the demo doesn't flash the
	// real "Connect to Agent" UI before the demo provider re-activates.
	const [endpoint, setEndpoint] = useState<AgentEndpoint>(() => {
		if (typeof window === "undefined") return localEndpoint;
		const stored = window.localStorage.getItem(STORAGE_KEY);
		return stored === "demo" ? DEMO_ENDPOINT : localEndpoint;
	});
	const [bootingDemo, setBootingDemo] = useState(false);

	// If we restored "demo" from localStorage, the worker hasn't actually been
	// started yet — kick it off on mount.
	useEffect(() => {
		if (endpoint.kind !== "demo") return;
		let cancelled = false;
		setBootingDemo(true);
		startDemoWorker()
			.catch((err) => {
				console.error("[demo] failed to start mock worker", err);
			})
			.finally(() => {
				if (!cancelled) setBootingDemo(false);
			});
		return () => {
			cancelled = true;
		};
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	const useDemo = useCallback(async () => {
		if (typeof window !== "undefined") {
			window.localStorage.setItem(STORAGE_KEY, "demo");
		}
		setBootingDemo(true);
		try {
			await startDemoWorker();
		} catch (err) {
			console.error("[demo] failed to start mock worker", err);
		} finally {
			setBootingDemo(false);
		}
		setEndpoint(DEMO_ENDPOINT);
	}, []);

	const useLocal = useCallback(() => {
		if (typeof window !== "undefined") {
			window.localStorage.removeItem(STORAGE_KEY);
		}
		setEndpoint(localEndpoint);
		// Stop the worker so subsequent local-agent requests pass through.
		void stopDemoWorker();
	}, [localEndpoint]);

	const value = useMemo<AgentEndpointContextValue>(
		() => ({
			endpoint,
			isDemo: endpoint.kind === "demo",
			bootingDemo,
			useDemo,
			useLocal,
		}),
		[endpoint, bootingDemo, useDemo, useLocal],
	);

	return (
		<AgentEndpointContext.Provider value={value}>
			{children}
		</AgentEndpointContext.Provider>
	);
}

export function useAgentEndpoint(): AgentEndpointContextValue {
	const ctx = useContext(AgentEndpointContext);
	if (!ctx) {
		throw new Error(
			"useAgentEndpoint must be used within <AgentEndpointProvider>",
		);
	}
	return ctx;
}

/** Convenience hook for landing-page CTAs that don't care about the rest of the API. */
export function useEnterDemo(): () => Promise<void> {
	return useAgentEndpoint().useDemo;
}
