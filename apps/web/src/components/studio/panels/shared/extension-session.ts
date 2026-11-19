import { z } from "zod";
import {
  ACTION_TIMEOUT_MS,
  REQUEST_TIMEOUT_MS,
  THEME_KEYS,
  type ThemeTokens,
} from "@stackpanel/extension-sdk/protocol";
import {
  dispatchExtensionCall,
  ExtensionDenied,
  ExtensionGrantInvalid,
  type ExtensionAuthority,
  type FrameOperations,
} from "./extension-policy";

export type PermissionLog = {
  id: number;
  method: string;
  outcome: "allowed" | "denied" | "failed";
};
const requestId = z.number().int().positive();
const envelope = z.discriminatedUnion("type", [
  z.strictObject({ type: z.literal("request"), id: requestId, call: z.unknown() }),
  z.strictObject({ type: z.literal("cancel"), id: requestId }),
]);
const offer = z.strictObject({ type: z.literal("stackpanel:ready"), nonce: z.string().length(32) });
const logLabel = z.object({
  method: z.enum([
    "getContext",
    "getConfig",
    "patchModuleConfig",
    "runAction",
    "proxyFetch",
    "toast",
  ]),
});

export interface ExtensionFrameSession {
  dispose(): void;
  publishConfig(): Promise<void>;
}

/** The WindowProxy survives iframe navigation. Never use it for data or RPC replies. */
export function bindExtensionFrame(
  frame: HTMLIFrameElement,
  nonce: string,
  authority: ExtensionAuthority,
  ops: FrameOperations,
  audit: (entry: PermissionLog) => void,
  navigated: () => void,
): ExtensionFrameSession {
  const controller = new AbortController();
  const { signal } = controller;
  let loaded = false;
  let port: MessagePort | undefined;
  let previousId = 0;
  const pending = new Map<number, AbortController>();
  let refresh: AbortController | undefined;
  let observer: MutationObserver | undefined;

  function sendTheme() {
    const style = getComputedStyle(document.documentElement);
    const tokens: ThemeTokens = {};
    for (const key of THEME_KEYS) tokens[key] = style.getPropertyValue(key).trim();
    port?.postMessage({ type: "theme", tokens });
  }

  async function publishConfig() {
    if (signal.aborted || !port || !authority.context.permissions.includes("config:read")) return;
    refresh?.abort();
    const read = new AbortController();
    refresh = read;
    const timer = window.setTimeout(() => read.abort(), REQUEST_TIMEOUT_MS);
    const clearDeadline = () => window.clearTimeout(timer);
    read.signal.addEventListener("abort", clearDeadline, { once: true });
    try {
      const settings = await ops.readConfig(read.signal);
      if (!read.signal.aborted) port.postMessage({ type: "config", settings });
    } catch (error) {
      if (!signal.aborted && error instanceof ExtensionGrantInvalid) revoke();
      else if (!read.signal.aborted) throw error;
    } finally {
      read.signal.removeEventListener("abort", clearDeadline);
      clearDeadline();
      if (refresh === read) refresh = undefined;
    }
  }

  async function request(event: MessageEvent<unknown>) {
    if (signal.aborted || !port) return;
    const parsed = envelope.safeParse(event.data);
    if (!parsed.success) return;
    if (parsed.data.type === "cancel") {
      pending.get(parsed.data.id)?.abort();
      return;
    }
    const { id, call } = parsed.data;
    // IDs are monotonic on a FIFO MessagePort. No unbounded seen-ID cache.
    if (typeof id !== "number" || !Number.isSafeInteger(id) || id <= previousId) return;
    previousId = id;
    if (pending.size >= 16) {
      port.postMessage({ type: "error", id, error: "Too many extension requests" });
      return;
    }
    const method = logLabel.safeParse(call).data?.method ?? "unknown";
    const operation = new AbortController();
    pending.set(id, operation);
    const timeout = method === "runAction" ? ACTION_TIMEOUT_MS : REQUEST_TIMEOUT_MS;
    const deadline = Date.now() + timeout;
    const timer = window.setTimeout(() => {
      if (operation.signal.aborted) return;
      operation.abort();
      port?.postMessage({ type: "error", id, error: "Extension operation timed out" });
      audit({ id, method, outcome: "failed" });
    }, timeout);
    const clearDeadline = () => window.clearTimeout(timer);
    operation.signal.addEventListener("abort", clearDeadline, { once: true });
    try {
      const value = await dispatchExtensionCall(call, authority, ops, operation.signal, deadline);
      if (operation.signal.aborted) return;
      port.postMessage({ type: "result", id, value });
      audit({ id, method, outcome: "allowed" });
      if (method === "patchModuleConfig") {
        // A read is a separate capability; patch-only panels never receive settings.
        void publishConfig().catch(() => {
          /* A refresh failure is not a second RPC result. */
        });
      }
    } catch (error) {
      if (signal.aborted) return;
      if (error instanceof ExtensionGrantInvalid) {
        if (!operation.signal.aborted)
          port.postMessage({ type: "error", id, error: "Extension grant is no longer valid" });
        revoke();
        return;
      }
      if (operation.signal.aborted) return;
      const denied = error instanceof ExtensionDenied;
      port.postMessage({
        type: "error",
        id,
        error: denied ? error.message : "Extension operation failed",
      });
      audit({ id, method, outcome: denied ? "denied" : "failed" });
    } finally {
      operation.signal.removeEventListener("abort", clearDeadline);
      clearDeadline();
      // Even an operation that ignores abort occupies a slot until it actually settles.
      pending.delete(id);
    }
  }

  function ready(event: MessageEvent<unknown>) {
    if (
      !loaded ||
      signal.aborted ||
      port ||
      !frame.isConnected ||
      !frame.contentWindow ||
      event.source !== frame.contentWindow ||
      event.origin !== "null" ||
      event.ports.length !== 1 ||
      offer.safeParse(event.data).data?.nonce !== nonce
    )
      return;
    port = event.ports[0];
    if (!port) return;
    port.onmessage = request;
    port.onmessageerror = revoke;
    port.addEventListener("close", revoke);
    port.postMessage({ type: "connected" });
    sendTheme();
    observer = new MutationObserver(sendTheme);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class", "style", "data-theme"],
    });
  }

  function load() {
    if (loaded) {
      revoke();
      return;
    }
    loaded = true;
    // No secrets or capabilities go to '*'. The initial document must prove
    // possession of its fragment nonce and transfer its own reply channel.
    frame.contentWindow?.postMessage({ type: "stackpanel:hello" }, "*");
  }
  function revoke() {
    if (signal.aborted) return;
    dispose();
    navigated();
  }
  function dispose() {
    if (signal.aborted) return;
    controller.abort();
    refresh?.abort();
    for (const operation of pending.values()) operation.abort();
    pending.clear();
    window.removeEventListener("message", ready);
    window.removeEventListener("pagehide", revoke);
    frame.removeEventListener("load", load);
    observer?.disconnect();
    if (port) {
      port.removeEventListener("close", revoke);
      port.onmessage = port.onmessageerror = null;
      port.close();
    }
  }
  window.addEventListener("message", ready);
  window.addEventListener("pagehide", revoke);
  frame.addEventListener("load", load);
  return { dispose, publishConfig };
}
