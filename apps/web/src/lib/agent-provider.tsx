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
import { useAgent, useAgentHealth } from "@/lib/use-agent";

const STORAGE_KEY = "stackpanel.agent.token";

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
 * Validate a token by checking the agent_id matches the current agent.
 * This avoids a network request by decoding the JWT locally.
 */
function validateTokenLocally(
	token: string,
	currentAgentId: string | null,
): boolean {
	if (!token || !currentAgentId) return false;

	const payload = decodeJWT(token);
	if (!payload) return false;

	// Check if agent_id matches
	if (payload.agent_id !== currentAgentId) {
		return false;
	}

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
	const [token, setToken] = useState<string | null>(null);
	const [tokenValidated, setTokenValidated] = useState(false);
	const cleanupRef = useRef<(() => void) | null>(null);

	useEffect(() => {
		setToken(localStorage.getItem(STORAGE_KEY));
		return () => {
			cleanupRef.current?.();
			cleanupRef.current = null;
		};
	}, []);

	const {
		status: healthStatus,
		projectRoot,
		agentId,
	} = useAgentHealth({
		host,
		port,
	});

	// Validate token locally when agent becomes available
	// This uses JWT decoding to check if the token's agent_id matches
	useEffect(() => {
		if (healthStatus !== "available" || !token || !agentId) {
			return;
		}

		const isValid = validateTokenLocally(token, agentId);
		if (isValid) {
			setTokenValidated(true);
		} else {
			// Token is invalid (agent probably restarted), clear it
			console.log("Stored token is invalid (agent_id mismatch), clearing...");
			localStorage.removeItem(STORAGE_KEY);
			setToken(null);
			setTokenValidated(false);
		}
	}, [healthStatus, token, agentId]);

	// Reset validation state when token changes
	useEffect(() => {
		if (!token) {
			setTokenValidated(false);
		}
	}, [token]);
	const agent = useAgent({
		host,
		port,
		token: token ?? undefined,
		autoConnect: true,
	});

	const clearPairing = useCallback(() => {
		localStorage.removeItem(STORAGE_KEY);
		setToken(null);
		setTokenValidated(false);
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
			setTokenValidated(true); // New token from pairing is valid

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

	// Consider "connected" if we have a validated token AND the agent is available.
	// Most functionality uses HTTP+tRPC with token auth, not WebSocket.
	// The WebSocket is only used for real-time features.
	const isConnected = healthStatus === "available" && !!token && tokenValidated;

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
