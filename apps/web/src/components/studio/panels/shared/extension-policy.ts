import type {
  ActionResult,
  ExtensionContext,
  JsonObject,
  JsonValue,
  Permission,
  ProxyOptions,
  ProxyResult,
} from "@stackpanel/extension-sdk/protocol";

/** Built by Studio from the evaluated module; never populated from the frame. */
export interface ExtensionAuthority {
  readonly projectId: string;
  readonly expiresAt: number;
  readonly context: ExtensionContext;
  readonly actions: ReadonlyMap<string, { confirm?: string; argsSchema?: JsonObject }>;
  readonly services: ReadonlySet<string>;
}

/** Operations are already bound to the host's project and module. */
export interface ExtensionOperations {
  readConfig(signal: AbortSignal): Promise<JsonObject>;
  patchConfig(settings: JsonObject, signal: AbortSignal): Promise<void>;
  runAction(action: string, args: JsonObject, signal: AbortSignal): Promise<ActionResult>;
  proxyFetch(
    service: string,
    path: string,
    options: ProxyOptions,
    signal: AbortSignal,
  ): Promise<ProxyResult>;
  toast(message: string): void;
}

// Transport alone cannot dispatch a frame request. The document owner must
// also supply its cancellable, trusted approval surface.
export interface FrameOperations extends ExtensionOperations {
  confirm(message: string, signal: AbortSignal): Promise<boolean>;
}

/** Only policy-generated messages are suitable to relay verbatim to the child. */
export class ExtensionDenied extends Error {
  override readonly name = "ExtensionDenied";
}

/** The host's previously evaluated grant no longer matches the active project. */
export class ExtensionGrantInvalid extends Error {
  override readonly name = "ExtensionGrantInvalid";

  constructor() {
    super("Extension grant is no longer valid.");
  }
}

function deny(message = "Invalid extension request."): never {
  throw new ExtensionDenied(message);
}

function plain(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype: unknown = Object.getPrototypeOf(value);
  return prototype === null || prototype === Object.prototype;
}

function dataValue(record: object, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  if (!descriptor?.enumerable || !Object.hasOwn(descriptor, "value")) deny();
  return descriptor.value;
}

function fields(
  value: unknown,
  required: readonly string[],
  optional: readonly string[] = [],
): asserts value is Record<string, unknown> {
  if (!plain(value)) deny();
  const keys = Reflect.ownKeys(value);
  if (keys.length > required.length + optional.length) deny();
  for (const key of keys) {
    if (typeof key !== "string" || !(required.includes(key) || optional.includes(key))) deny();
    dataValue(value, key);
  }
  if (!required.every((key) => Object.hasOwn(value, key))) deny();
}

const maxDepth = 16;
const maxNodes = 4096;
// Aggregate UTF-16 code units across all keys and string values, not per leaf.
const maxText = 64 * 1024;
const configRoots = {
  stackpanel: true,
  apps: true,
  imports: true,
  _module: true,
  secrets: true,
  variables: true,
} as const;
const relativeAttribute = /^[A-Za-z0-9_-]+$/;

function jsonObject(value: unknown, relativeSettings: boolean): asserts value is JsonObject {
  if (!plain(value)) deny();
  let nodes = maxNodes;
  let text = maxText;

  function visit(item: unknown, depth: number): void {
    if (--nodes < 0 || depth > maxDepth) deny("Extension data exceeds the allowed limit.");
    if (item === null || typeof item === "boolean" || Number.isFinite(item)) return;
    if (typeof item === "string") {
      if ((text -= item.length) < 0) deny("Extension data exceeds the allowed limit.");
      return;
    }
    if (Array.isArray(item)) {
      if (Object.getPrototypeOf(item) !== Array.prototype || item.length > nodes) deny();
      if (Reflect.ownKeys(item).length !== item.length + 1) deny();
      for (let i = 0; i < item.length; i++) visit(dataValue(item, String(i)), depth + 1);
      return;
    }
    if (!plain(item)) deny();
    const keys = Reflect.ownKeys(item);
    if (keys.length > nodes) deny("Extension data exceeds the allowed limit.");
    for (const key of keys) {
      if (typeof key !== "string" || (text -= key.length) < 0) deny();
      if (key === "prototype" || Object.hasOwn(Object.prototype, key)) deny();
      if (relativeSettings && (!relativeAttribute.test(key) || Object.hasOwn(configRoots, key))) {
        deny("Only relative module settings are allowed.");
      }
      visit(dataValue(item, key), depth + 1);
    }
  }
  visit(value, 0);
}

const unsafePathChar = /[^A-Za-z0-9._~/-]/;
const dotSegment = /(?:^|\/)\.{1,2}(?:\/|$)/;

function proxyPath(value: unknown): string {
  // Accept a literal path, never a URL to resolve or a string to decode.
  if (
    typeof value !== "string" ||
    value.length > 2048 ||
    !value.startsWith("/") ||
    value.includes("//") ||
    unsafePathChar.test(value) ||
    dotSegment.test(value)
  ) {
    deny("Invalid service path.");
  }
  return value;
}

const unsafeHeaderChar = /[^\x20-\x7e]/;

function proxyHeaders(raw: unknown): Record<string, string> {
  if (!plain(raw)) deny("Invalid proxy headers.");
  const keys = Reflect.ownKeys(raw);
  if (keys.length > 2) deny("Invalid proxy headers.");
  const headers: Record<string, string> = {};
  for (const key of keys) {
    if (typeof key !== "string" || key.length > "content-type".length)
      deny("Invalid proxy header.");
    const name = key.toLowerCase();
    if ((name !== "accept" && name !== "content-type") || Object.hasOwn(headers, name)) {
      deny("Invalid proxy header.");
    }
    const value = dataValue(raw, key);
    if (typeof value !== "string" || value.length > 1024 || unsafeHeaderChar.test(value)) {
      deny("Invalid proxy header value.");
    }
    headers[name] = value;
  }
  return headers;
}

function proxyOptions(raw: unknown): ProxyOptions {
  fields(raw, [], ["method", "headers", "body"]);
  const options: ProxyOptions = {};
  if (Object.hasOwn(raw, "method")) {
    const method = raw.method;
    if (
      method !== "GET" &&
      method !== "POST" &&
      method !== "PUT" &&
      method !== "PATCH" &&
      method !== "DELETE"
    ) {
      deny("Invalid proxy method.");
    }
    options.method = method;
  }
  if (Object.hasOwn(raw, "body")) {
    if (
      !options.method ||
      options.method === "GET" ||
      typeof raw.body !== "string" ||
      raw.body.length > maxText
    ) {
      deny("Invalid proxy body.");
    }
    options.body = raw.body;
  }
  if (Object.hasOwn(raw, "headers")) options.headers = proxyHeaders(raw.headers);
  return options;
}

// Never ask someone to approve a truncated action summary.
const maxReviewLength = 1024;
const sensitiveName =
  /password|passwd|passphrase|secret|token|credential|authorization|cookie|apikey|accesskey|privatekey|signingkey|sshkey|bearer/i;
const indirectSchema = [
  "$ref",
  "$dynamicRef",
  "$recursiveRef",
  "allOf",
  "anyOf",
  "oneOf",
  "not",
  "if",
  "then",
  "else",
  "patternProperties",
  "dependentSchemas",
  "dependencies",
  "prefixItems",
  "contains",
  "unevaluatedItems",
  "unevaluatedProperties",
];

function unreviewable(): never {
  return deny("Action details cannot be safely reviewed.");
}

// JSON quotes disambiguate newlines, quotes and backslashes. Escaping non-ASCII
// also prevents bidi controls, Unicode line breaks and lookalikes from impersonating labels.
function quoted(value: string): string {
  if (value.length > maxReviewLength) unreviewable();
  return JSON.stringify(value).replace(
    /[^\x20-\x7e]/g,
    (ch) => `\\u${ch.charCodeAt(0).toString(16).padStart(4, "0")}`,
  );
}

function reviewArgument(value: JsonValue, schema: unknown, key: string): string {
  if (!plain(schema) || indirectSchema.some((keyword) => Object.hasOwn(schema, keyword)))
    unreviewable();
  if (
    sensitiveName.test(key.replace(/[^a-z0-9]/gi, "")) ||
    schema.writeOnly === true ||
    schema.sensitive === true ||
    schema.secret === true ||
    schema["x-sensitive"] === true ||
    schema["x-secret"] === true ||
    schema["x-stackpanel-sensitive"] === true ||
    schema["x-stackpanel-secret"] === true ||
    (typeof schema.format === "string" && /secret|password|token|credential/i.test(schema.format))
  ) {
    // Do not hide an entire batch of operations behind a single redacted label.
    if (value !== null && typeof value === "object") unreviewable();
    return "[redacted]";
  }

  if (Array.isArray(value)) {
    return `[${value.map((item) => reviewArgument(item, schema.items, "")).join(", ")}]`;
  }
  if (value !== null && typeof value === "object") {
    const entries = [];
    for (const [name, item] of Object.entries(value)) {
      // A dynamic/unknown column may contain a secret, or a target hidden by
      // redaction. Neither echo it nor silently omit it and approve the rest.
      if (!plain(schema.properties) || !Object.hasOwn(schema.properties, name)) unreviewable();
      entries.push(`${quoted(name)}: ${reviewArgument(item, schema.properties[name], name)}`);
    }
    return `{${entries.join(", ")}}`;
  }
  return typeof value === "string" ? quoted(value) : JSON.stringify(value);
}

function reviewTarget({ projectId, context }: ExtensionAuthority): string[] {
  const { moduleId, panelId, appId } = context;
  if (
    !projectId?.trim() ||
    !moduleId?.trim() ||
    !panelId?.trim() ||
    (appId !== undefined && !appId.trim())
  ) {
    throw new ExtensionGrantInvalid();
  }
  return [
    `Project: ${quoted(projectId)}`,
    `Module: ${quoted(moduleId)}`,
    `Panel: ${quoted(panelId)}`,
    `App: ${appId === undefined ? "(none)" : quoted(appId)}`,
  ];
}

function actionConfirmation(
  authority: ExtensionAuthority,
  action: string,
  args: JsonObject,
  schema: JsonObject | undefined,
  note: string | undefined,
): string {
  if (!action.trim()) throw new ExtensionGrantInvalid();
  if (note !== undefined && !note.trim()) deny("Action not confirmed.");
  if (JSON.stringify(args).length > maxReviewLength) unreviewable();
  const message = [
    "Run this action? Module code can access the network and change project data.",
    ...reviewTarget(authority),
    `Action: ${quoted(action)}`,
    `Arguments: ${reviewArgument(args, schema ?? {}, "")}`,
    ...(note === undefined ? [] : [`Module-provided note: ${quoted(note)}`]),
    "Once started, cancelling does not roll back changes.",
  ].join("\n");
  if (message.length > maxReviewLength) unreviewable();
  return message;
}

function requireGrant(context: ExtensionContext, grant: Permission): void {
  if (!context.permissions.includes(grant)) deny("Permission not granted.");
}

function requireLiveRequest(authority: ExtensionAuthority, signal: AbortSignal, deadline: number) {
  signal.throwIfAborted();
  const now = Date.now();
  if (!Number.isSafeInteger(authority.expiresAt) || now >= authority.expiresAt) {
    throw new ExtensionGrantInvalid();
  }
  // The tab can be suspended during review before its timeout callback runs.
  if (!(now < deadline)) deny("Extension operation timed out.");
}

export async function dispatchExtensionCall(
  raw: unknown,
  authority: ExtensionAuthority,
  ops: FrameOperations,
  signal: AbortSignal,
  deadline = authority.expiresAt,
): Promise<unknown> {
  requireLiveRequest(authority, signal, deadline);
  if (!plain(raw)) deny();
  const { context } = authority;
  switch (dataValue(raw, "method")) {
    case "getContext": {
      fields(raw, ["method"]);
      const { moduleId, panelId, permissions, appId } = context;
      return { moduleId, panelId, permissions, ...(appId === undefined ? {} : { appId }) };
    }
    case "getConfig":
      fields(raw, ["method"]);
      requireGrant(context, "config:read");
      return await ops.readConfig(signal);
    case "patchModuleConfig":
      fields(raw, ["method", "settings"]);
      requireGrant(context, "config:patch");
      jsonObject(raw.settings, true);
      return await ops.patchConfig(raw.settings, signal);
    case "runAction": {
      fields(raw, ["method", "action", "args"]);
      requireGrant(context, "actions:run");
      const { action: id, args } = raw;
      if (typeof id !== "string" || !id || id.length > 256) deny("Action not allowed.");
      const action = authority.actions.get(id);
      if (!action) deny("Action not allowed.");
      jsonObject(args, false);
      const message = actionConfirmation(authority, id, args, action.argsSchema, action.confirm);
      requireLiveRequest(authority, signal, deadline);
      if ((await ops.confirm(message, signal)) !== true) deny("Action not confirmed.");
      requireLiveRequest(authority, signal, deadline);
      return await ops.runAction(id, args, signal);
    }
    case "proxyFetch": {
      fields(raw, ["method", "service", "path", "options"]);
      requireGrant(context, "service:proxy");
      const { service } = raw;
      if (
        typeof service !== "string" ||
        !service ||
        service.length > 256 ||
        unsafePathChar.test(service) ||
        service.includes("/") ||
        dotSegment.test(service) ||
        !authority.services.has(service)
      ) {
        deny("Service not allowed.");
      }
      const path = proxyPath(raw.path);
      const options = proxyOptions(raw.options);
      // Review only the validated routing metadata, never headers, credentials
      // or body text. Dispatch the same validated snapshot, once.
      const message = [
        "Send this service request? The panel will be able to read the response.",
        ...reviewTarget(authority),
        `Method: ${options.method ?? "GET"}`,
        `Service: ${quoted(service)}`,
        `Path: ${path}`,
        `Body: ${options.body === undefined ? "none" : "present (not shown)"}`,
      ].join("\n");
      requireLiveRequest(authority, signal, deadline);
      if ((await ops.confirm(message, signal)) !== true) deny("Service request not approved.");
      requireLiveRequest(authority, signal, deadline);
      return await ops.proxyFetch(service, path, options, signal);
    }
    case "toast":
      fields(raw, ["method", "message"]);
      if (typeof raw.message !== "string" || raw.message.length > 512 || !raw.message.trim()) {
        deny("Invalid toast message.");
      }
      return ops.toast(raw.message);
    default:
      deny("Unknown extension operation.");
  }
}
