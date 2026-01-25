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
import { AgentHttpClient } from "./agent";
import { useAgent, useAgentHealth } from "@/lib/use-agent";

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
		const jsonPayload = atob(base64);
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
}: AgentProviderProps) {
	// Initialize token synchronously to prevent flash of "Connect to Agent"
	const [token, setToken] = useState<string | null>(getInitialToken);
	const cleanupRef = useRef<(() => void) | null>(null);

	// Handle query token persistence and URL cleanup (runs after initial render)
	useEffect(() => {
		const urlParams = new URLSearchParams(window.location.search);
		const queryToken = urlParams.get("token");

		if (queryToken && queryToken.length >= 10) {
			// Token provided via query parameter - persist to localStorage
			localStorage.setItem(STORAGE_KEY, queryToken);

			// Clean up URL by removing the token parameter
			urlParams.delete("token");
			const newUrl =
				urlParams.toString().length > 0
					? `${window.location.pathname}?${urlParams.toString()}`
					: window.location.pathname;
			window.history.replaceState({}, "", newUrl);
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
	}, [token]);

	const { status: healthStatus, projectRoot } = useAgentHealth({
		host,
		port,
	});

	const agent = useAgent({
		host,
		port,
		token: token ?? undefined,
		autoConnect: true,
	});

	const clearPairing = useCallback(() => {
		localStorage.removeItem(STORAGE_KEY);
		setToken(null);
		agent.disconnect();
	}, [agent]);

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
	// The server validates the token on each request - if the token is invalid
	// (e.g., agent was restarted), the server will reject it and we'll get an error.
	// This avoids the UX issue of requiring re-pairing after every agent restart.
	const isConnected = healthStatus === "available" && !!token;

	const value = useMemo<AgentContextValue>(
		() => ({
			host,
			port,
			healthStatus,
			projectRoot,
			token,
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
			token,
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
