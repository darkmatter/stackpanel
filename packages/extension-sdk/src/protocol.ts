export type JsonValue = null | boolean | number | string | JsonValue[] | JsonObject;
export interface JsonObject {
  [key: string]: JsonValue;
}

export type Permission = "config:read" | "config:patch" | "actions:run" | "service:proxy";

export interface ExtensionContext {
  moduleId: string;
  panelId: string;
  permissions: Permission[];
  /** Present only when Studio mounted this panel within an app. */
  appId?: string;
}

export interface ProxyOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  headers?: Record<string, string>;
  body?: string;
}

export interface ProxyResult {
  status: number;
  body: string;
  contentType: string;
}

export interface ActionResult {
  stdout: string;
  stderr: string;
  exitCode: number;
  json?: JsonValue;
}

// Studio sends a snapshot of computed values, not a stylesheet or arbitrary CSS.
export const THEME_KEYS = [
  "--background",
  "--foreground",
  "--card",
  "--card-foreground",
  "--popover",
  "--popover-foreground",
  "--primary",
  "--primary-foreground",
  "--secondary",
  "--secondary-foreground",
  "--muted",
  "--muted-foreground",
  "--accent",
  "--accent-foreground",
  "--destructive",
  "--destructive-foreground",
  "--border",
  "--input",
  "--ring",
  "--radius",
  "--font-sans",
  "--font-mono",
  "--chart-1",
  "--chart-2",
  "--chart-3",
  "--chart-4",
  "--chart-5",
  "--sidebar",
  "--sidebar-foreground",
  "--sidebar-primary",
  "--sidebar-primary-foreground",
  "--sidebar-accent",
  "--sidebar-accent-foreground",
  "--sidebar-border",
  "--sidebar-ring",
] as const;

export type ThemeTokens = Partial<Record<(typeof THEME_KEYS)[number], string>>;

/** Window messages are for discovery only; `ready` transfers exactly one new port. */
export type HandshakeMessage =
  | { type: "stackpanel:hello" }
  | { type: "stackpanel:ready"; nonce: string };

export type ExtensionCall =
  | { method: "getContext" }
  | { method: "getConfig" }
  | { method: "patchModuleConfig"; settings: JsonObject }
  | { method: "runAction"; action: string; args: JsonObject }
  | { method: "proxyFetch"; service: string; path: string; options: ProxyOptions }
  | { method: "toast"; message: string };

export interface ExtensionRequest {
  type: "request";
  id: number;
  call: ExtensionCall;
}

export type ExtensionMessage = ExtensionRequest | { type: "cancel"; id: number };

// The host enforces its own deadline even for panels that never send cancel.
export const REQUEST_TIMEOUT_MS = 30_000;
export const ACTION_TIMEOUT_MS = 5 * 60_000;

/** Only messages arriving over the acknowledged channel can complete a request. */
export type HostMessage =
  | { type: "connected" }
  | { type: "result"; id: number; value: unknown }
  | { type: "error"; id: number; error: string }
  | { type: "theme"; tokens: ThemeTokens }
  | { type: "config"; settings: JsonObject };
