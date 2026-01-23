/**
 * Hook for subscribing to Server-Sent Events from the agent.
 * Provides real-time updates for shell status, config changes, etc.
 */

import { useEffect, useState, useCallback, useRef } from "react";
import { useAgentContext } from "./agent-provider";
import { useAgentSSEEvent } from "./agent-sse-provider";

interface SSEEvent {
	event: string;
	data: unknown;
}

interface UseSSEOptions {
	/** Events to subscribe to (if empty, subscribes to all) */
	events?: string[];
	/** Callback when an event is received */
	onEvent?: (event: SSEEvent) => void;
	/** Whether to automatically reconnect on disconnect */
	autoReconnect?: boolean;
	/** Reconnect delay in ms */
	reconnectDelay?: number;
}

/**
 * Hook for subscribing to SSE events from the agent.
 * 
 * @deprecated Use `useAgentSSEEvent` from `agent-sse-provider` instead.
 * This hook creates its own EventSource connection, whereas `useAgentSSEEvent`
 * uses the shared connection from `AgentSSEProvider`.
 */
export function useSSE(options: UseSSEOptions = {}) {
	const { 
		events, 
		onEvent, 
		autoReconnect = true,
		reconnectDelay = 3000,
	} = options;
	
	const { host, port, token, isConnected } = useAgentContext();
	const [connected, setConnected] = useState(false);
	const [lastEvent, setLastEvent] = useState<SSEEvent | null>(null);
	const eventSourceRef = useRef<EventSource | null>(null);
	const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	
	// Use refs for values that shouldn't trigger reconnection
	const eventsRef = useRef(events);
	const onEventRef = useRef(onEvent);
	const autoReconnectRef = useRef(autoReconnect);
	const reconnectDelayRef = useRef(reconnectDelay);
	
	// Update refs when values change
	useEffect(() => {
		eventsRef.current = events;
	}, [events]);
	
	useEffect(() => {
		onEventRef.current = onEvent;
	}, [onEvent]);
	
	useEffect(() => {
		autoReconnectRef.current = autoReconnect;
	}, [autoReconnect]);
	
	useEffect(() => {
		reconnectDelayRef.current = reconnectDelay;
	}, [reconnectDelay]);

	const connect = useCallback(() => {
		if (!isConnected || !token) return;

		// Clean up existing connection
		if (eventSourceRef.current) {
			eventSourceRef.current.close();
		}

		const url = `http://${host}:${port}/api/events?token=${encodeURIComponent(token)}`;
		const eventSource = new EventSource(url);
		eventSourceRef.current = eventSource;

		eventSource.onopen = () => {
			setConnected(true);
		};

		eventSource.onerror = () => {
			setConnected(false);
			eventSource.close();
			eventSourceRef.current = null;

			// Auto-reconnect
			if (autoReconnectRef.current && isConnected) {
				reconnectTimeoutRef.current = setTimeout(() => {
					connect();
				}, reconnectDelayRef.current);
			}
		};

		// Listen to specific events or all events
		const handleEvent = (e: MessageEvent) => {
			try {
				const data = JSON.parse(e.data);
				const sseEvent: SSEEvent = { event: e.type, data };
				
				setLastEvent(sseEvent);
				onEventRef.current?.(sseEvent);
			} catch {
				// Ignore parse errors
			}
		};

		const currentEvents = eventsRef.current;
		if (currentEvents && currentEvents.length > 0) {
			// Subscribe to specific events
			for (const eventName of currentEvents) {
				eventSource.addEventListener(eventName, handleEvent);
			}
		} else {
			// Subscribe to all events via onmessage
			eventSource.onmessage = handleEvent;
		}

		// Also listen for the connected event
		eventSource.addEventListener("connected", (e) => {
			try {
				const data = JSON.parse(e.data);
				setLastEvent({ event: "connected", data });
			} catch {
				// Ignore
			}
		});

	}, [host, port, token, isConnected]);

	// Connect when agent becomes available
	useEffect(() => {
		if (isConnected && token) {
			connect();
		}

		return () => {
			if (eventSourceRef.current) {
				eventSourceRef.current.close();
				eventSourceRef.current = null;
			}
			if (reconnectTimeoutRef.current) {
				clearTimeout(reconnectTimeoutRef.current);
				reconnectTimeoutRef.current = null;
			}
		};
	}, [isConnected, token, connect]);

	return {
		connected,
		lastEvent,
		reconnect: connect,
	};
}

/**
 * Hook specifically for shell status SSE events.
 * Automatically updates when shell becomes stale or is rebuilt.
 * 
 * NOTE: This hook requires AgentSSEProvider to be mounted in the component tree.
 * It uses the shared SSE connection from the provider instead of creating its own.
 */
export function useShellStatusSSE(onStatusChange?: (stale: boolean) => void) {
	const [isStale, setIsStale] = useState(false);
	const [isRebuilding, setIsRebuilding] = useState(false);
	const [lastChangedFile, setLastChangedFile] = useState<string | null>(null);
	
	// Store callback in ref to avoid re-subscribing on every render
	const onStatusChangeRef = useRef(onStatusChange);
	useEffect(() => {
		onStatusChangeRef.current = onStatusChange;
	}, [onStatusChange]);

	// Uses the shared AgentSSEProvider connection instead of creating a new one
	useAgentSSEEvent("shell.stale", (data: { file?: string }) => {
		setIsStale(true);
		if (data.file) {
			setLastChangedFile(data.file);
		}
		onStatusChangeRef.current?.(true);
	});
	
	useAgentSSEEvent("shell.rebuilding", () => {
		setIsRebuilding(true);
	});
	
	useAgentSSEEvent("shell.rebuilt", () => {
		setIsStale(false);
		setIsRebuilding(false);
		setLastChangedFile(null);
		onStatusChangeRef.current?.(false);
	});

	return {
		isStale,
		isRebuilding,
		lastChangedFile,
	};
}
