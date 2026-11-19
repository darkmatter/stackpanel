import { connectToStudio } from "./channel.js";
import type {
  ActionResult,
  ExtensionCall,
  ExtensionContext,
  JsonObject,
  ProxyOptions,
  ProxyResult,
} from "./protocol.js";
import { createThemeSync } from "./theme.js";

export type {
  ActionResult,
  ExtensionContext,
  JsonObject,
  JsonValue,
  Permission,
  ProxyOptions,
  ProxyResult,
} from "./protocol.js";

type ConfigListener = (settings: JsonObject) => void;

interface Results {
  getContext: ExtensionContext;
  getConfig: JsonObject;
  patchModuleConfig: void;
  runAction: ActionResult;
  proxyFetch: ProxyResult;
  toast: void;
}

export interface ExtensionClient {
  getContext(): Promise<ExtensionContext>;
  getConfig(): Promise<JsonObject>;
  patchModuleConfig(settings: JsonObject): Promise<void>;
  runAction(action: string, args?: JsonObject, signal?: AbortSignal): Promise<ActionResult>;
  proxyFetch(service: string, path: string, options?: ProxyOptions): Promise<ProxyResult>;
  toast(message: string): Promise<void>;
  onConfigChange(listener: ConfigListener): () => void;
  dispose(): void;
}

/** Bind a client to this iframe document. Dispose it before replacing the document or client. */
export function createExtensionClient(frame: Window): ExtensionClient {
  const listeners = new Set<ConfigListener>();
  const applyTheme = createThemeSync(frame);
  let disposed = false;
  const channel = connectToStudio(
    frame,
    (message) => {
      if (message.type === "theme") {
        applyTheme(message.tokens);
      } else {
        for (const listener of listeners) listener(message.settings);
      }
    },
    () => {
      disposed = true;
      listeners.clear();
      applyTheme({});
    },
  );

  function call<C extends ExtensionCall>(
    payload: C,
    signal?: AbortSignal,
  ): Promise<Results[C["method"]]> {
    // Only the acknowledged host port can resolve this request's unique ID.
    return channel.request(payload, signal) as Promise<Results[C["method"]]>;
  }

  return {
    getContext: () => call({ method: "getContext" }),
    getConfig: () => call({ method: "getConfig" }),
    patchModuleConfig: (settings: JsonObject) => call({ method: "patchModuleConfig", settings }),
    runAction: (action, args = {}, signal) => call({ method: "runAction", action, args }, signal),
    proxyFetch: (service: string, path: string, options: ProxyOptions = {}) =>
      call({ method: "proxyFetch", service, path, options }),
    toast: (message: string) => call({ method: "toast", message }),
    onConfigChange(listener: ConfigListener): () => void {
      if (disposed) throw new Error("Studio extension connection closed");
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    dispose: channel.dispose,
  };
}

let shared: ExtensionClient | undefined;
function client(): ExtensionClient {
  if (typeof window === "undefined") throw new Error("The extension SDK requires a Studio iframe");
  return (shared ??= createExtensionClient(window));
}

// Importing the package is inert in SSR, the host window, and the iframe. The
// first call or subscription offers the port, even if the host's hello has passed.
export async function getContext(): Promise<ExtensionContext> {
  return await client().getContext();
}

export async function getConfig(): Promise<JsonObject> {
  return await client().getConfig();
}

/** Merge a settings object into the host-bound module. There is no path or target argument. */
export async function patchModuleConfig(settings: JsonObject): Promise<void> {
  await client().patchModuleConfig(settings);
}

/** Aborting requests cancellation of the host operation; it cannot undo completed side effects. */
export async function runAction(
  action: string,
  args: JsonObject = {},
  signal?: AbortSignal,
): Promise<ActionResult> {
  return await client().runAction(action, args, signal);
}

export async function proxyFetch(
  service: string,
  path: string,
  options: ProxyOptions = {},
): Promise<ProxyResult> {
  return await client().proxyFetch(service, path, options);
}

export async function toast(message: string): Promise<void> {
  await client().toast(message);
}

/** Returns an unsubscribe function. Use getConfig() for the initial snapshot. */
export function onConfigChange(listener: ConfigListener): () => void {
  return client().onConfigChange(listener);
}
