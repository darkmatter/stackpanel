"use client";

import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useEffect,
	useMemo,
	useRef,
	useState,
} from "react";
import { AgentHttpClient, AGENT_AUTH_ERROR_EVENT } from "./agent";
import { useAgent, useAgentHealth } from "@/lib/use-agent";
import { useAgentSSEOptional } from "@/lib/agent-sse-provider";

const STORAGE_KEY = "stackpanel.agent.token";

/**
 * Get the initial token from localStorage (runs synchronously during useState init).
 * This prevents a flash of "Connect to Agent" on page refresh.
 */
function getInitialToken(): string | null {
	if (typeof window === "undefined") return null;
	
	// Check for token in query parameter first
	const urlParams = new URLSearchParams(window.location.search);
	const queryToken = urlParams.get("token");
	if (queryToken && queryToken.length >= 10) {
		return queryToken;
	}
	
	// Otherwise try localStorage
	return localStorage.getItem(STORAGE_KEY);
}

/**
 * Decode a JWT token without verifying the signature.
 * Returns the payload or null if invalid.
 */
function decodeJWT(token: string): { agent_id?: string; exp?: number } | null {
	try {
		const parts = token.split(".");
		if (parts.length !== 3) return null;

		// Decode the payload (second part)
		const payload = parts[1];
		// Handle URL-safe base64
		const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
		const padding = "=".repeat((4 - (base64.length % 4)) % 4);
		const jsonPayload = atob(`${base64}${padding}`);
		return JSON.parse(jsonPayload);
	} catch {
		return null;
	}
}

/**
 * Check if a token is expired by decoding the JWT and checking the exp claim.
 * Returns true if token is valid (not expired), false if expired or invalid.
 */
function isTokenNotExpired(token: string): boolean {
	const payload = decodeJWT(token);
	if (!payload) return false;

	// Check if token is expired
	if (payload.exp) {
		const now = Math.floor(Date.now() / 1000);
		if (payload.exp < now) {
			return false;
		}
	}

	return true;
}

type AgentProviderProps = {
	children: ReactNode;
	host?: string;
	port?: number;
	token?: string | null;
};

type AgentContextValue = {
	host: string;
	port: number;
	healthStatus: "checking" | "available" | "unavailable";
	projectRoot: string | null;
	token: string | null;
	isConnected: boolean;
	isConnecting: boolean;
	error: Error | null;
	pair: () => void;
	clearPairing: () => void;
	connect: () => Promise<void>;
	disconnect: () => void;
	exec: (command: string, args?: string[]) => Promise<unknown>;
	nixEval: <T = unknown>(expression: string) => Promise<T>;
	nixGenerate: () => Promise<unknown>;
	readFile: (path: string) => Promise<unknown>;
	writeFile: (path: string, content: string) => Promise<void>;
	setSecret: (
		env: "dev" | "staging" | "prod",
		key: string,
		value: string,
	) => Promise<unknown>;
};

const AgentContext = createContext<AgentContextValue | null>(null);

export function AgentProvider({
	children,
	host = "localhost",
	port = 9876,
	token: providedToken,
}: AgentProviderProps) {
	// Initialize token synchronously to prevent flash of "Connect to Agent"
	const [token, setToken] = useState<string | null>(
		() => providedToken ?? getInitialToken(),
	);
	const cleanupRef = useRef<(() => void) | null>(null);
	const effectiveToken = providedToken ?? token;

	// Handle query token persistence and URL cleanup (runs after initial render)
	useEffect(() => {
		if (providedToken !== undefined) {
			return () => {
				cleanupRef.current?.();
				cleanupRef.current = null;
			};
		}

		const urlParams = new URLSearchParams(window.location.search);
		const queryToken = urlParams.get("token");

		if (queryToken && queryToken.length >= 10) {
			// Token provided via query parameter - persist to localStorage
			localStorage.setItem(STORAGE_KEY, queryToken);
			if (token !== queryToken) {
				setToken(queryToken);
			}

			// Clean up URL by removing the token parameter
			urlParams.delete("token");
			const newUrl =
				urlParams.toString().length > 0
					? `${window.location.pathname}?${urlParams.toString()}`
					: window.location.pathname;
			window.history.replaceState({}, "", newUrl);
		} else if (!token) {
			const storedToken = localStorage.getItem(STORAGE_KEY);
			if (!storedToken) {
				return;
			}

			if (!isTokenNotExpired(storedToken)) {
				localStorage.removeItem(STORAGE_KEY);
				return;
			}

			setToken(storedToken);
		} else if (token) {
			// Check if stored token is expired
			if (!isTokenNotExpired(token)) {
				console.log("Stored token is expired, clearing...");
				localStorage.removeItem(STORAGE_KEY);
				setToken(null);
			}
		}

		return () => {
			cleanupRef.current?.();
			cleanupRef.current = null;
		};
	}, [providedToken, token]);

	// Use SSE for health status when available (provides instant disconnect detection)
	const sse = useAgentSSEOptional();

	// SSE provides connection info (projectRoot, hasProject) via the "connected" event
	// Only poll when SSE is not connected yet (initial discovery before pairing)
	const sseIsHealthy = sse?.status === "connected" && sse.isAlive;
	const { status: polledHealthStatus, projectRoot: polledProjectRoot } = useAgentHealth({
		host,
		port,
		// Disable polling when SSE is healthy (set very long interval)
		// Only poll for initial discovery when no SSE connection
		intervalMs: sseIsHealthy ? 300_000 : 5_000, // 5 min when SSE healthy, 5s otherwise
	});

	// Use SSE connectionInfo when available, fall back to polled values
	const projectRoot = sse?.connectionInfo?.projectRoot ?? polledProjectRoot;

	// Derive health status: prefer SSE when connected and alive, fall back to polling
	// Only trust SSE status when it's actually connected - "error" could mean no token yet
	const healthStatus = (() => {
		if (sseIsHealthy) {
			return "available" as const;
		}
		// SSE had a connection but lost it (was alive, now not) - agent disconnected
		if (sse?.status === "error" && sse.lastHeartbeat !== null) {
			return "unavailable" as const;
		}
		// SSE not connected yet (no token, connecting, never connected) - use polling
		return polledHealthStatus;
	})();

	const agent = useAgent({
		host,
		port,
		token: effectiveToken ?? undefined,
		autoConnect: true,
	});

	const clearPairing = useCallback(() => {
		localStorage.removeItem(STORAGE_KEY);
		setToken(null);
		agent.disconnect();
	}, [agent]);

	// Listen for 401 auth errors from any agent request (HTTP client or Connect-RPC).
	// When the agent restarts, it generates new signing keys, invalidating all tokens.
	// This clears the stale token so the pairing UI shows up again.
	useEffect(() => {
		const handleAuthError = () => {
			console.log("Agent auth error (401) - clearing stale token for re-pairing");
			localStorage.removeItem(STORAGE_KEY);
			setToken(null);
		};
		window.addEventListener(AGENT_AUTH_ERROR_EVENT, handleAuthError);
		return () => window.removeEventListener(AGENT_AUTH_ERROR_EVENT, handleAuthError);
	}, []);

	// Validate the stored token when the agent becomes available.
	// This catches cases where the token is stale (e.g., agent restarted with new keys)
	// before the user makes any API call that would trigger a 401.
	useEffect(() => {
		if (healthStatus !== "available" || !effectiveToken) return;

		let cancelled = false;
		const validateToken = async () => {
			try {
				const res = await fetch(`http://${host}:${port}/api/auth/validate`, {
					headers: { "X-Stackpanel-Token": effectiveToken },
				});
				if (!cancelled && res.status === 401) {
					console.log("Stored token is invalid (agent may have restarted), clearing for re-pairing");
					localStorage.removeItem(STORAGE_KEY);
					setToken(null);
				}
			} catch {
				// Agent unreachable - health polling will handle this
			}
		};
		validateToken();
		return () => { cancelled = true; };
	}, [effectiveToken, healthStatus, host, port]);

	const pair = useCallback(() => {
		// Open the local agent pairing page (localhost) in a popup.
		const origin = window.location.origin;
		const pairUrl = `http://${host}:${port}/pair?origin=${encodeURIComponent(origin)}`;

		const popup = window.open(
			pairUrl,
			"stackpanel-agent-pair",
			"popup,width=560,height=620",
		);

		if (!popup) {
			// Popup blocked.
			return;
		}

		const allowedPairOrigins = new Set([
			`http://${host}:${port}`,
			`http://localhost:${port}`,
			`http://127.0.0.1:${port}`,
		]);

		const onMessage = (event: MessageEvent) => {
			if (!allowedPairOrigins.has(event.origin)) return;
			const data = event.data as { type?: string; token?: unknown } | null;
			if (!data || data.type !== "stackpanel.agent.pair") return;
			if (typeof data.token !== "string" || data.token.length < 10) return;

			localStorage.setItem(STORAGE_KEY, data.token);
			setToken(data.token);

			window.removeEventListener("message", onMessage);
			cleanupRef.current = null;
		};

		window.addEventListener("message", onMessage);
		cleanupRef.current = () => window.removeEventListener("message", onMessage);

		// Safety cleanup.
		window.setTimeout(() => {
			cleanupRef.current?.();
			cleanupRef.current = null;
		}, 5 * 60_000);
	}, [host, port]);

	// Consider "connected" if we have a token AND the agent is available.
	// When SSE is connected and alive, we get instant disconnect detection.
	// The server validates the token on each request - if the token is invalid
	// (e.g., agent was restarted), the server will reject it and we'll get an error.
	const isConnected = healthStatus === "available" && !!effectiveToken;

	const value = useMemo<AgentContextValue>(
		() => ({
			host,
			port,
			healthStatus,
			projectRoot,
			token: effectiveToken,
			isConnected,
			isConnecting: agent.isConnecting,
			error: agent.error,
			pair,
			clearPairing,
			connect: agent.connect,
			disconnect: agent.disconnect,
			exec: agent.exec,
			nixEval: agent.nixEval,
			nixGenerate: agent.nixGenerate,
			readFile: agent.readFile,
			writeFile: agent.writeFile,
			setSecret: agent.setSecret,
		}),
		[
			agent.connect,
			agent.disconnect,
			agent.error,
			agent.exec,
			agent.isConnecting,
			agent.nixEval,
			agent.nixGenerate,
			agent.readFile,
			agent.setSecret,
			agent.writeFile,
			clearPairing,
			healthStatus,
			host,
			isConnected,
			pair,
			port,
			projectRoot,
			effectiveToken,
		],
	);

	return (
		<AgentContext.Provider value={value}>{children}</AgentContext.Provider>
	);
}

export function useAgentContext(): AgentContextValue {
	const ctx = useContext(AgentContext);
	if (!ctx) {
		throw new Error("useAgentContext must be used within <AgentProvider>");
	}
	return ctx;
}

/**
 * Hook to get a shared AgentHttpClient instance.
 * Uses the host, port, and token from the AgentProvider context.
 */
export function useAgentClient(): AgentHttpClient {
	const { host, port, token } = useAgentContext();
	return useMemo(
		() => new AgentHttpClient({ host, port, token: token ?? undefined }),
		[host, port, token],
	);
}
