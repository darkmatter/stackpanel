/// <reference lib="es2024.promise" />
import {
  ACTION_TIMEOUT_MS,
  REQUEST_TIMEOUT_MS,
  type ExtensionCall,
  type ExtensionMessage,
  type ExtensionRequest,
  type HandshakeMessage,
  type HostMessage,
} from "./protocol.js";

const MAX_PENDING = 16;
const BRIDGE_HASH = /^#stackpanel-bridge=([\da-f]{32})$/i;

type Notification = Extract<HostMessage, { type: "theme" | "config" }>;

interface Pending {
  queued: ExtensionRequest | undefined;
  timer: number;
  unsubscribe?: () => void;
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
}

export function connectToStudio(
  frame: Window & { MessageChannel?: typeof MessageChannel },
  notify: (message: Notification) => void,
  onDispose: () => void,
) {
  if (!frame.parent || frame === frame.parent) {
    throw new Error("The extension SDK requires a Studio iframe");
  }
  const nonce = BRIDGE_HASH.exec(frame.location.hash)?.[1];
  if (!nonce) throw new Error("Missing Studio iframe handshake");

  const parent = frame.parent;
  const ready: HandshakeMessage = { type: "stackpanel:ready", nonce };
  const Channel = frame.MessageChannel ?? MessageChannel;
  const offers = new Set<MessagePort>();
  const pending = new Map<number, Pending>();
  let port: MessagePort | undefined;
  let nextId = 1;
  let closed = false;

  function take(id: number) {
    const entry = pending.get(id);
    if (entry) {
      frame.clearTimeout(entry.timer);
      entry.unsubscribe?.();
      pending.delete(id);
    }
    return entry;
  }

  function cancel(id: number, error: Error) {
    const entry = take(id);
    if (!entry) return;
    if (!entry.queued && port) {
      try {
        port.postMessage({ type: "cancel", id } satisfies ExtensionMessage);
      } catch {
        /* A closed port is independently revoked by Studio. */
      }
    }
    entry.reject(error);
  }

  function send(accepted: MessagePort, entry: Pending) {
    const request = entry.queued;
    if (!request) return;
    entry.queued = undefined;
    try {
      accepted.postMessage(request);
    } catch {
      take(request.id)?.reject(new Error(`Cannot send ${request.call.method} to Studio`));
    }
  }

  function closePort(candidate: MessagePort) {
    candidate.onmessage = null;
    candidate.onmessageerror = null;
    candidate.removeEventListener("close", onPortClose);
    candidate.close();
  }

  function onPortClose(event: Event) {
    if (event.currentTarget === port) dispose();
    else {
      for (const candidate of offers) {
        if (candidate === event.currentTarget) {
          offers.delete(candidate);
          closePort(candidate);
        }
      }
    }
  }

  function receive(candidate: MessagePort, message: HostMessage) {
    if (closed || !message || typeof message !== "object") return;
    if (!port && message.type === "connected" && offers.has(candidate)) {
      port = candidate;
      frame.removeEventListener("message", onHello);
      for (const offer of offers) if (offer !== port) closePort(offer);
      offers.clear();
      for (const entry of pending.values()) send(port, entry);
      return;
    }
    if (port !== candidate) return;
    switch (message.type) {
      case "result":
        take(message.id)?.resolve(message.value);
        break;
      case "error":
        take(message.id)?.reject(new Error(message.error));
        break;
      case "theme":
      case "config":
        notify(message);
        break;
    }
  }

  function offerPort() {
    // The eager offer may precede iframe load. Keep it alive while offering a
    // second channel on hello: its ack may already be queued. No RPC is sent
    // on either one until Studio acknowledges exactly one of them.
    if (closed || port || offers.size >= 2) return;
    const { port1, port2 } = new Channel();
    offers.add(port1);
    port1.onmessage = (event: MessageEvent<HostMessage>) => receive(port1, event.data);
    port1.onmessageerror = onPortClose;
    port1.addEventListener("close", onPortClose);
    try {
      // The embedding origin is not known; only the handshake and fresh port
      // go over WindowProxy. Both credentials and RPC stay out of this message.
      parent.postMessage(ready, "*", [port2]);
    } catch {
      offers.delete(port1);
      closePort(port1);
      port2.close();
      throw new Error("Cannot connect to the Studio iframe host");
    }
  }

  function onHello(event: MessageEvent<unknown>) {
    if (event.source !== parent) return;
    const { data } = event;
    if (data && typeof data === "object" && "type" in data && data.type === "stackpanel:hello") {
      offerPort();
    }
  }

  function onPageHide(event: PageTransitionEvent) {
    if (!event.persisted) dispose();
  }

  function dispose() {
    if (closed) return;
    closed = true;
    frame.removeEventListener("message", onHello);
    frame.removeEventListener("pagehide", onPageHide);
    for (const id of pending.keys()) cancel(id, new Error("Studio extension connection closed"));
    if (port) closePort(port);
    port = undefined;
    for (const candidate of offers) closePort(candidate);
    offers.clear();
    onDispose();
  }

  function request(call: ExtensionCall, signal?: AbortSignal): Promise<unknown> {
    if (signal?.aborted)
      return Promise.reject(new DOMException("Extension call aborted", "AbortError"));
    if (closed) return Promise.reject(new Error("Studio extension connection closed"));
    if (pending.size >= MAX_PENDING)
      return Promise.reject(new Error("Too many pending Studio calls"));
    const id = nextId++;
    const request: ExtensionRequest = { type: "request", id, call };
    const { promise, resolve, reject } = Promise.withResolvers<unknown>();
    const { method } = call;
    const timeout = method === "runAction" ? ACTION_TIMEOUT_MS : REQUEST_TIMEOUT_MS;
    const timer = frame.setTimeout(() => {
      cancel(id, new Error(`Studio ${method} timed out`));
    }, timeout);
    const entry: Pending = { queued: request, timer, resolve, reject };
    pending.set(id, entry);
    if (signal) {
      const onAbort = () => cancel(id, new DOMException("Extension call aborted", "AbortError"));
      signal.addEventListener("abort", onAbort, { once: true });
      entry.unsubscribe = () => signal.removeEventListener("abort", onAbort);
    }
    if (port) send(port, entry);
    return promise;
  }

  frame.addEventListener("message", onHello);
  frame.addEventListener("pagehide", onPageHide);
  try {
    offerPort();
  } catch (error) {
    dispose();
    throw error;
  }
  return { request, dispose };
}
