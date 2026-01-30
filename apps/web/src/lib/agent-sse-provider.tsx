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

const STORAGE_KEY = "stackpanel.agent.token";

/**
 * How often we expect heartbeats from the server (milliseconds).
 * Server sends ping every 5 seconds, so we allow some buffer.
 */
const HEARTBEAT_TIMEOUT_MS = 12_000;

export type AgentSSEStatus = "idle" | "connecting" | "connected" | "error";

export type AgentSSEEvent = {
	event: string;
	data: unknown;
	receivedAt: number;
	rawEvent: MessageEvent<string>;
};

type AgentSSEListener = (event: AgentSSEEvent) => void;

/** Data received from the SSE "connected" event */
export type AgentSSEConnectionInfo = {
	projectRoot: string | null;
	hasProject: boolean;
	agentId: string | null;
};

type AgentSSEContextValue = {
	status: AgentSSEStatus;
	error: Error | null;
	lastEvent: AgentSSEEvent | null;
	/** Timestamp of last heartbeat ping from server */
	lastHeartbeat: number | null;
	/** True if connected and receiving heartbeats */
	isAlive: boolean;
	/** Connection info from the "connected" event (projectRoot, hasProject, agentId) */
	connectionInfo: AgentSSEConnectionInfo | null;
	connect: () => void;
	disconnect: () => void;
	addEventListener: (event: string, listener: AgentSSEListener) => () => void;
};

type AgentSSEProviderProps = {
	children: ReactNode;
	host?: string;
	port?: number;
	token?: string | null;
	autoConnect?: boolean;
};

const AgentSSEContext = createContext<AgentSSEContextValue | null>(null);

function parseEventData(raw: string) {
	try {
		return JSON.parse(raw) as unknown;
	} catch {
		return raw;
	}
}

export function AgentSSEProvider({
	children,
	host = "localhost",
	port = 9876,
	token,
	autoConnect = true,
}: AgentSSEProviderProps) {
	const [storedToken, setStoredToken] = useState<string | null>(null);
	const [status, setStatus] = useState<AgentSSEStatus>("idle");
	const [error, setError] = useState<Error | null>(null);
	const [lastEvent, setLastEvent] = useState<AgentSSEEvent | null>(null);
	const [lastHeartbeat, setLastHeartbeat] = useState<number | null>(null);
	const [isAlive, setIsAlive] = useState(false);
	const [connectionInfo, setConnectionInfo] = useState<AgentSSEConnectionInfo | null>(null);
	const eventSourceRef = useRef<EventSource | null>(null);
	const listenersRef = useRef<Map<string, Set<AgentSSEListener>>>(new Map());
	const registeredEventsRef = useRef<Map<string, EventListener>>(new Map());
	const heartbeatTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

	const resolvedToken = token !== undefined ? token : storedToken;

	useEffect(() => {
		if (token !== undefined) return;
		setStoredToken(localStorage.getItem(STORAGE_KEY));

		const onStorage = (event: StorageEvent) => {
			if (event.key === STORAGE_KEY) {
				setStoredToken(event.newValue);
			}
		};

		window.addEventListener("storage", onStorage);
		return () => window.removeEventListener("storage", onStorage);
	}, [token]);

	// Reset heartbeat timeout - called on each heartbeat or connection
	const resetHeartbeatTimeout = useCallback(() => {
		// Clear existing timeout
		if (heartbeatTimeoutRef.current) {
			clearTimeout(heartbeatTimeoutRef.current);
		}
		// Mark as alive
		setIsAlive(true);
		// Set timeout to mark as stale if no heartbeat received
		heartbeatTimeoutRef.current = setTimeout(() => {
			setIsAlive(false);
			setStatus("error");
			setError(new Error("Connection stale (no heartbeat)"));
		}, HEARTBEAT_TIMEOUT_MS);
	}, []);

	const dispatchEvent = useCallback(
		(eventName: string, rawEvent: MessageEvent) => {
			const data = parseEventData(String(rawEvent.data));
			const event: AgentSSEEvent = {
				event: eventName,
				data,
				receivedAt: Date.now(),
				rawEvent: rawEvent as MessageEvent<string>,
			};
			setLastEvent(event);

			const listeners = listenersRef.current.get(eventName);
			if (listeners) {
				for (const listener of listeners) {
					listener(event);
				}
			}

			const wildcardListeners = listenersRef.current.get("*");
			if (wildcardListeners) {
				for (const listener of wildcardListeners) {
					listener(event);
				}
			}

			if (eventName === "connected") {
				setStatus("connected");
				resetHeartbeatTimeout();
				// Extract connection info from the connected event
				const connData = data as { projectRoot?: string; hasProject?: boolean; agentId?: string } | null;
				if (connData && typeof connData === "object") {
					setConnectionInfo({
						projectRoot: connData.projectRoot ?? null,
						hasProject: connData.hasProject ?? false,
						agentId: connData.agentId ?? null,
					});
				}
			}

			// Handle heartbeat pings
			if (eventName === "ping") {
				setLastHeartbeat(Date.now());
				resetHeartbeatTimeout();
			}
		},
		[resetHeartbeatTimeout],
	);

	const attachEventListener = useCallback(
		(eventName: string) => {
			if (!eventSourceRef.current) return;
			if (registeredEventsRef.current.has(eventName)) return;

			const handler: EventListener = (event) => {
				dispatchEvent(eventName, event as MessageEvent);
			};

			registeredEventsRef.current.set(eventName, handler);
			eventSourceRef.current.addEventListener(eventName, handler);
		},
		[dispatchEvent],
	);

	const connect = useCallback(() => {
		if (eventSourceRef.current) return;
		if (!resolvedToken) {
			setStatus("error");
			setError(new Error("Missing agent token (pair first)"));
			return;
		}

		setStatus("connecting");
		setError(null);

		const url = new URL(`http://${host}:${port}/api/events`);
		url.searchParams.set("token", resolvedToken);
		const eventSource = new EventSource(url.toString());
		eventSourceRef.current = eventSource;

		eventSource.onopen = () => {
			setStatus("connected");
			setError(null);
		};

		eventSource.onerror = () => {
			setStatus("error");
			setError(new Error("SSE connection error"));
			setIsAlive(false);
			// Clear heartbeat timeout on error
			if (heartbeatTimeoutRef.current) {
				clearTimeout(heartbeatTimeoutRef.current);
				heartbeatTimeoutRef.current = null;
			}
		};

		// Always listen for connected and ping events for keepalive
		attachEventListener("connected");
		attachEventListener("ping");
		for (const eventName of listenersRef.current.keys()) {
			if (eventName === "*") continue;
			attachEventListener(eventName);
		}
	}, [attachEventListener, host, port, resolvedToken]);

	const disconnect = useCallback(() => {
		// Clear heartbeat timeout
		if (heartbeatTimeoutRef.current) {
			clearTimeout(heartbeatTimeoutRef.current);
			heartbeatTimeoutRef.current = null;
		}
		if (eventSourceRef.current) {
			for (const [eventName, handler] of registeredEventsRef.current) {
				eventSourceRef.current.removeEventListener(eventName, handler);
			}
			registeredEventsRef.current.clear();
			eventSourceRef.current.close();
			eventSourceRef.current = null;
		}
		setStatus("idle");
		setIsAlive(false);
		setLastHeartbeat(null);
		setConnectionInfo(null);
	}, []);

	const addEventListener = useCallback(
		(eventName: string, listener: AgentSSEListener) => {
			const listeners = listenersRef.current.get(eventName) ?? new Set();
			listeners.add(listener);
			listenersRef.current.set(eventName, listeners);
			if (eventName !== "*") {
				attachEventListener(eventName);
			}

			return () => {
				const current = listenersRef.current.get(eventName);
				if (!current) return;
				current.delete(listener);
				if (current.size === 0) {
					listenersRef.current.delete(eventName);
					const handler = registeredEventsRef.current.get(eventName);
					if (handler && eventSourceRef.current) {
						eventSourceRef.current.removeEventListener(eventName, handler);
					}
					registeredEventsRef.current.delete(eventName);
				}
			};
		},
		[attachEventListener],
	);

	useEffect(() => {
		if (!autoConnect) return;
		if (!resolvedToken) {
			disconnect();
			setError(null);
			return;
		}
		disconnect();
		connect();
		return () => disconnect();
	}, [autoConnect, connect, disconnect, resolvedToken]);

	const value = useMemo<AgentSSEContextValue>(
		() => ({
			status,
			error,
			lastEvent,
			lastHeartbeat,
			isAlive,
			connectionInfo,
			connect,
			disconnect,
			addEventListener,
		}),
		[addEventListener, connect, connectionInfo, disconnect, error, isAlive, lastEvent, lastHeartbeat, status],
	);

	return (
		<AgentSSEContext.Provider value={value}>
			{children}
		</AgentSSEContext.Provider>
	);
}

export function useAgentSSE(): AgentSSEContextValue {
	const ctx = useContext(AgentSSEContext);
	if (!ctx) {
		throw new Error("useAgentSSE must be used within <AgentSSEProvider>");
	}
	return ctx;
}

/**
 * Optional hook that returns SSE context if available, otherwise null.
 * Useful for components that can work with or without SSE.
 */
export function useAgentSSEOptional(): AgentSSEContextValue | null {
	return useContext(AgentSSEContext);
}

export function useAgentSSEEvent<T = unknown>(
	eventName: string,
	handler?: (data: T, event: AgentSSEEvent) => void,
) {
	const { addEventListener } = useAgentSSE();
	const [data, setData] = useState<T | null>(null);
	const [event, setEvent] = useState<AgentSSEEvent | null>(null);
	
	// Use ref for handler to avoid re-subscribing when handler changes
	const handlerRef = useRef(handler);
	useEffect(() => {
		handlerRef.current = handler;
	}, [handler]);

	useEffect(() => {
		return addEventListener(eventName, (nextEvent) => {
			setEvent(nextEvent);
			setData(nextEvent.data as T);
			handlerRef.current?.(nextEvent.data as T, nextEvent);
		});
	}, [addEventListener, eventName]);

	return { data, event };
}
