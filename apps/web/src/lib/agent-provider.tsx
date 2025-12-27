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
	const cleanupRef = useRef<(() => void) | null>(null);

	useEffect(() => {
		setToken(localStorage.getItem(STORAGE_KEY));
		return () => {
			cleanupRef.current?.();
			cleanupRef.current = null;
		};
	}, []);

	const { status: healthStatus, projectRoot } = useAgentHealth({ host, port });
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

	const value = useMemo<AgentContextValue>(
		() => ({
			host,
			port,
			healthStatus,
			projectRoot,
			token,
			isConnected: agent.isConnected,
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
			agent.isConnected,
			agent.isConnecting,
			agent.nixEval,
			agent.nixGenerate,
			agent.readFile,
			agent.setSecret,
			agent.writeFile,
			clearPairing,
			healthStatus,
			host,
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
