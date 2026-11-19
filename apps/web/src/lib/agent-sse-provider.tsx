"use client";

import { createParser, type EventSourceMessage } from "eventsource-parser";
import {
  createContext,
  type ReactNode,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { canonicalAgentOrigin, checkAgentIdentity } from "./agent-identity";

/**
 * How often we expect heartbeats from the server (milliseconds).
 * Server sends ping every 5 seconds, so we allow some buffer.
 */
const HEARTBEAT_TIMEOUT_MS = 12_000;
const RECONNECT_DELAY_MS = 3_000;

export type AgentSSEStatus = "idle" | "connecting" | "connected" | "error";

export type AgentSSEEvent = {
  event: string;
  data: unknown;
  receivedAt: number;
  rawEvent: MessageEvent<string>;
};

const DEV_DIAGNOSTICS = "module.dev.diagnostics";

type AgentSSEListener = (event: AgentSSEEvent) => void;

/** Data received from the SSE "connected" event */
export type AgentSSEConnectionInfo = {
  projectRoot: string | null;
  hasProject: boolean;
  agentId: string | null;
};

type StreamState = {
  status: AgentSSEStatus;
  error: Error | null;
  lastEvent: AgentSSEEvent | null;
  /** Timestamp of last heartbeat ping from server */
  lastHeartbeat: number | null;
  /** True if connected and receiving heartbeats */
  isAlive: boolean;
  /** Connection info from the "connected" event (projectRoot, hasProject, agentId) */
  connectionInfo: AgentSSEConnectionInfo | null;
};

type AgentSSEContextValue = StreamState & {
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
  setupSession?: string;
  projectId?: string;
};

const AgentSSEContext = createContext<AgentSSEContextValue | null>(null);

function parseEventData(raw: string) {
  try {
    return JSON.parse(raw) as unknown;
  } catch {
    return raw;
  }
}

const idle: StreamState = {
  status: "idle",
  error: null,
  lastEvent: null,
  lastHeartbeat: null,
  isAlive: false,
  connectionInfo: null,
};

function getConnectionInfo(data: unknown): AgentSSEConnectionInfo | null {
  if (!data || typeof data !== "object") return null;
  return {
    projectRoot:
      "projectRoot" in data && typeof data.projectRoot === "string" ? data.projectRoot : null,
    hasProject: "hasProject" in data && data.hasProject === true,
    agentId: "agentId" in data && typeof data.agentId === "string" ? data.agentId : null,
  };
}

// One owner per credential, endpoint and project/setup scope. Neither a late
// read nor a newly mounted listener can publish/replay into a different scope.
function createAgentStream(
  host: string,
  port: number,
  token: string | null | undefined,
  projectId?: string,
  setupSession?: string,
) {
  const listeners = new Map<string, Set<AgentSSEListener>>();
  const observers = new Set<() => void>();
  let snapshot: AgentSSEContextValue = { ...idle, connect, disconnect, addEventListener };
  let diagnostics: AgentSSEEvent | null = null;
  let attempt: AbortController | null = null;
  let heartbeat: ReturnType<typeof setTimeout> | undefined;
  let retry: ReturnType<typeof setTimeout> | undefined;
  let disposed = false;

  function update(patch: Partial<StreamState>) {
    snapshot = { ...snapshot, ...patch };
    for (const observer of observers) observer();
  }

  function stop() {
    clearTimeout(heartbeat);
    clearTimeout(retry);
    attempt?.abort();
    attempt = null;
  }

  function disconnect() {
    stop();
    diagnostics = null;
    update(idle);
  }

  function reconnect(error: Error) {
    stop();
    // Keep the scoped snapshot across a dropped stream, but not if checking
    // identity or opening its authenticated replacement failed.
    if (snapshot.status === "connecting") diagnostics = null;
    retry = setTimeout(connect, RECONNECT_DELAY_MS);
    update({ ...idle, status: "error", error, lastHeartbeat: snapshot.lastHeartbeat });
  }

  function expectHeartbeat() {
    clearTimeout(heartbeat);
    heartbeat = setTimeout(
      () => reconnect(new Error("Connection stale (no heartbeat)")),
      HEARTBEAT_TIMEOUT_MS,
    );
  }

  function addEventListener(name: string, listener: AgentSSEListener) {
    const subscribers = listeners.get(name) ?? new Set<AgentSSEListener>();
    listeners.set(name, subscribers);
    subscribers.add(listener);
    if (name === DEV_DIAGNOSTICS && diagnostics) listener(diagnostics);
    return () => {
      subscribers.delete(listener);
      if (!subscribers.size && listeners.get(name) === subscribers) listeners.delete(name);
    };
  }

  function dispatch(message: EventSourceMessage, streamOrigin: string) {
    const name = message.event || "message";
    const data = parseEventData(message.data);
    if (name === DEV_DIAGNOSTICS) {
      if (!projectId && !setupSession) return;
      if (projectId && getDiagnosticProject(data) !== projectId) return;
    }
    const receivedAt = Date.now();
    const event: AgentSSEEvent = {
      event: name,
      data,
      receivedAt,
      rawEvent: new MessageEvent(name, {
        data: message.data,
        origin: streamOrigin,
        lastEventId: message.id ?? "",
      }),
    };
    if (name === DEV_DIAGNOSTICS) diagnostics = event;
    if (name === "connected" || name === "ping") expectHeartbeat();
    update({
      lastEvent: event,
      ...(name === "connected" && { isAlive: true, connectionInfo: getConnectionInfo(data) }),
      ...(name === "ping" && { isAlive: true, lastHeartbeat: receivedAt }),
    });
    notify(listeners.get(name), event);
    if (name !== "*") notify(listeners.get("*"), event);
  }

  async function open(credential: string, signal: AbortSignal) {
    // A new agent can take over the same port between attempts. Never send
    // the bearer (including on redirects) based on an earlier health check.
    const url = new URL("/api/events", canonicalAgentOrigin(host, port));
    if (setupSession) url.searchParams.set("setup", setupSession);
    if (projectId) url.searchParams.set("project", projectId);
    await checkAgentIdentity(url.origin, credential, signal);
    if (signal.aborted) return;
    const response = await fetch(url, {
      headers: { Accept: "text/event-stream", Authorization: `Bearer ${credential}` },
      signal,
      redirect: "error",
      credentials: "omit",
      cache: "no-store",
      referrerPolicy: "no-referrer",
    });
    if (signal.aborted) {
      await response.body?.cancel();
      return;
    }
    // HTTP 204 explicitly disables SSE (e.g. the polling-only demo agent).
    if (response.status === 204) {
      disconnect();
      return;
    }
    const mediaType = response.headers.get("Content-Type")?.split(";", 1)[0]?.trim().toLowerCase();
    if (response.status !== 200 || mediaType !== "text/event-stream" || !response.body) {
      throw new Error(`Invalid agent event stream (HTTP ${response.status})`);
    }

    expectHeartbeat();
    update({ status: "connected" });
    await readEvents(response.body, signal, (message) => {
      if (!signal.aborted) dispatch(message, url.origin);
    });
    if (!signal.aborted) reconnect(new Error("Agent event stream ended"));
  }

  function connect() {
    if (disposed || attempt) return;
    if (!token) {
      update({ status: "error", error: new Error("Missing agent token (pair first)") });
      return;
    }
    clearTimeout(retry);
    attempt = new AbortController();
    const { signal } = attempt;
    update({ status: "connecting", error: null });
    void open(token, signal).catch((cause: unknown) => {
      if (!signal.aborted)
        reconnect(cause instanceof Error ? cause : new Error("SSE connection error"));
    });
  }

  return {
    getSnapshot: () => snapshot,
    subscribe: (observer: () => void) => {
      observers.add(observer);
      return () => {
        observers.delete(observer);
      };
    },
    mount(autoConnect: boolean) {
      disposed = false;
      if (autoConnect && token) connect();
      return () => {
        disposed = true;
        disconnect();
      };
    },
  };
}

function getDiagnosticProject(data: unknown) {
  if (data && typeof data === "object" && "projectId" in data) return data.projectId;
  return null;
}

async function readEvents(
  body: ReadableStream<Uint8Array>,
  signal: AbortSignal,
  onEvent: (message: EventSourceMessage) => void,
) {
  const decoder = new TextDecoder();
  const parser = createParser({ onEvent });
  const reader = body.getReader();
  const cancel = () => {
    // Aborting fetch may have already errored the body.
    void reader.cancel().catch(() => {});
  };
  signal.addEventListener("abort", cancel);
  try {
    if (signal.aborted) cancel();
    while (!signal.aborted) {
      const { done, value } = await reader.read();
      if (signal.aborted) break;
      if (done) {
        parser.feed(decoder.decode());
        break;
      }
      parser.feed(decoder.decode(value, { stream: true }));
    }
  } finally {
    signal.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
}

function notify(listeners: Set<AgentSSEListener> | undefined, event: AgentSSEEvent) {
  if (!listeners) return;
  for (const listener of listeners) {
    try {
      listener(event);
    } catch (error) {
      // A subscriber error must not tear down the stream for everyone else.
      reportError(error);
    }
  }
}

export function AgentSSEProvider({
  children,
  host = "localhost",
  port = 9876,
  token,
  autoConnect = true,
  setupSession,
  projectId,
}: AgentSSEProviderProps) {
  const stream = useMemo(
    () => createAgentStream(host, port, token, projectId, setupSession),
    [host, port, token, projectId, setupSession],
  );

  useLayoutEffect(() => stream.mount(autoConnect), [stream, autoConnect]);
  const value = useSyncExternalStore(stream.subscribe, stream.getSnapshot, stream.getSnapshot);

  return <AgentSSEContext.Provider value={value}>{children}</AgentSSEContext.Provider>;
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
  const [received, setReceived] = useState<{
    owner: typeof addEventListener;
    name: string;
    event: AgentSSEEvent;
  } | null>(null);

  // Use ref for handler to avoid re-subscribing when handler changes
  const handlerRef = useRef(handler);
  useEffect(() => {
    handlerRef.current = handler;
  }, [handler]);

  useEffect(() => {
    return addEventListener(eventName, (nextEvent) => {
      setReceived({ owner: addEventListener, name: eventName, event: nextEvent });
      handlerRef.current?.(nextEvent.data as T, nextEvent);
    });
  }, [addEventListener, eventName]);

  const event =
    received?.owner === addEventListener && received.name === eventName ? received.event : null;
  return { data: event ? (event.data as T) : null, event };
}
