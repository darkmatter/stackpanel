import { Code, ConnectError, type Client } from "@connectrpc/connect";
import type { Permission, ProxyResult } from "@stackpanel/extension-sdk/protocol";
import type { ModuleService, OpenModuleUIRequest } from "@stackpanel/proto/agent/v1/module";
import { toast } from "sonner";
import { fetchWithAgentIdentity } from "@/lib/agent-identity";
import { collectExtensionAction } from "./extension-action-stream";
import {
  ExtensionGrantInvalid,
  type ExtensionAuthority,
  type ExtensionOperations,
} from "./extension-policy";
import { bridgeNonce, extensionFrameUrl } from "./extension-url";
import { hasActionReview, isJsonObject } from "./panel-data";

export interface ExtensionTarget {
  client: Client<typeof ModuleService>;
  projectId: string;
  reviewRevision: string;
  moduleId: string;
  panelId: string;
  appId?: string;
  agentOrigin: string;
  token: string;
}

export function isReviewRevision(value: unknown): value is string {
  return typeof value === "string" && value.length === 64 && !/[^0-9a-f]/.test(value);
}

const maxResponseBytes = 1024 * 1024;
const maxGrantLifetimeMs = 60 * 60 * 1000;
export const grantHeader = "X-Stackpanel-UI-Grant";
const isPermission = (value: unknown): value is Permission =>
  value === "config:read" ||
  value === "config:patch" ||
  value === "actions:run" ||
  value === "service:proxy";

export function isPanelPermissions(value: unknown): value is Permission[] {
  return Array.isArray(value) && value.every(isPermission);
}

/** Only an explicit host approval may acquire a grant. Refreshes never use this path. */
export async function openReviewedUI(
  client: Client<typeof ModuleService>,
  request: Pick<OpenModuleUIRequest, "moduleId" | "panelId" | "reviewRevision"> &
    Partial<Pick<OpenModuleUIRequest, "appId" | "statusAction" | "statusApps">>,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  if (!isReviewRevision(request.reviewRevision)) throw new ExtensionGrantInvalid();
  let headers: Headers | undefined;
  const opened = await client.openModuleUI(request, {
    signal,
    timeoutMs: 30_000,
    onHeader(value) {
      headers = value;
    },
  });
  signal.throwIfAborted();
  if (opened.reviewRevision !== request.reviewRevision) throw new ExtensionGrantInvalid();
  const grant = headers?.get(grantHeader);
  const seconds = headers?.get("X-Stackpanel-UI-Expires-At");
  const expiresAt = Number(seconds) * 1000;
  const now = Date.now();
  if (
    !grant ||
    /[\s,]/.test(grant) ||
    !seconds ||
    /\D/.test(seconds) ||
    !Number.isSafeInteger(expiresAt) ||
    expiresAt <= now ||
    expiresAt > now + maxGrantLifetimeMs
  ) {
    throw new Error("Agent returned no valid UI grant.");
  }
  return { opened, grant, expiresAt };
}

async function readProxyResult(response: Response): Promise<ProxyResult> {
  // Do not expose agent headers, redirect targets, cookies, or response URLs.
  if (response.redirected || (response.status >= 300 && response.status < 400))
    throw new Error("Redirect refused");
  const result = {
    status: response.status,
    contentType: response.headers.get("Content-Type") ?? "",
    body: "",
  };
  if (!response.body) return result;
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > maxResponseBytes) {
        await reader.cancel();
        throw new Error("Service response exceeds the extension limit");
      }
      result.body += decoder.decode(chunk.value, { stream: true });
    }
    result.body += decoder.decode();
    return result;
  } finally {
    reader.releaseLock();
  }
}

export interface OpenExtension {
  url: string;
  source: { kind: "bundle" | "dev"; origin: string };
  nonce: string;
  authority: ExtensionAuthority;
  ops: ExtensionOperations;
}

/** This is exactly what the user reviewed. It can constrain the launch,
 * never supply the asset URL or grant operations of its own. */
export interface DocumentPreview {
  source: OpenExtension["source"];
  projectId: string;
  context: { moduleId: string; panelId: string; appId?: string; permissions: readonly string[] };
}

export async function openExtension(
  target: ExtensionTarget,
  reviewed: DocumentPreview,
  signal: AbortSignal,
): Promise<OpenExtension> {
  signal.throwIfAborted();
  const { client, moduleId, panelId, appId, agentOrigin, projectId, token } = target;
  const { reviewRevision } = target;
  if (
    reviewed.projectId !== projectId ||
    reviewed.context.moduleId !== moduleId ||
    reviewed.context.panelId !== panelId ||
    reviewed.context.appId !== appId
  )
    throw new ExtensionGrantInvalid();
  // Captured once per document, never renewed by the SDK and never included
  // in either its context or its asset URL. The server binds it to the exact
  // project, app, panel and evaluated capability revision.
  const { opened, grant, expiresAt } = await openReviewedUI(
    client,
    { moduleId, panelId, appId, reviewRevision },
    signal,
  );
  const header = { [grantHeader]: grant };
  const asset = extensionFrameUrl(agentOrigin, window.location.origin, moduleId, panelId, opened);
  const source: OpenExtension["source"] = {
    kind: opened.devUrl ? "dev" : "bundle",
    origin: asset.origin,
  };
  // Never keep a ticket for a second review, or discover additional services
  // on the strength of an inconsistent response. Start from a fresh snapshot.
  if (
    source.kind !== reviewed.source.kind ||
    source.origin !== reviewed.source.origin ||
    !isPanelPermissions(opened.permissions) ||
    !opened.permissions.every((p) => reviewed.context.permissions.includes(p)) ||
    !reviewed.context.permissions.every((p) => opened.permissions.includes(p))
  )
    throw new ExtensionGrantInvalid();
  const permissions = opened.permissions;
  if (
    permissions.includes("config:read")
      ? !isJsonObject(opened.settings)
      : opened.settings !== undefined
  )
    throw new Error("Invalid settings for this panel's permissions.");
  if (
    !Array.isArray(opened.actionIds) ||
    !isJsonObject(opened.actions) ||
    opened.actionIds.length !== Object.keys(opened.actions).length ||
    new Set(opened.actionIds).size !== opened.actionIds.length ||
    (!permissions.includes("actions:run") && opened.actionIds.length !== 0)
  ) {
    throw new Error("Invalid panel action allowlist.");
  }
  const actions = new Map(
    opened.actionIds.map((id) => {
      const action = opened.actions[id];
      if (!id.trim() || !Object.hasOwn(opened.actions, id) || !action || !hasActionReview(action))
        throw new Error("Missing action approval metadata.");
      return [id, action] as const;
    }),
  );
  const services = new Set<string>();
  if (permissions.includes("service:proxy")) {
    const { outputs } = await client.getModuleOutputs({ moduleId }, { signal });
    signal.throwIfAborted();
    if (outputs?.moduleId !== moduleId) throw new Error("Service ownership is unavailable");
    for (const svc of outputs.services) if (svc.proxyEnabled === true) services.add(svc.name);
  }
  const authority: ExtensionAuthority = {
    projectId,
    expiresAt,
    context: { moduleId, panelId, ...(appId ? { appId } : {}), permissions },
    actions,
    services,
  };
  async function bound<T>(call: () => Promise<T>): Promise<T> {
    if (Date.now() >= expiresAt) throw new ExtensionGrantInvalid();
    try {
      return await call();
    } catch (err) {
      if (
        err instanceof ConnectError &&
        (err.code === Code.PermissionDenied || err.code === Code.Unauthenticated)
      ) {
        throw new ExtensionGrantInvalid();
      }
      throw err;
    }
  }
  const ops: ExtensionOperations = {
    async readConfig(signal) {
      const next = await bound(() =>
        client.openModuleUI({ moduleId, panelId, appId }, { signal, headers: header }),
      );
      if (next.reviewRevision !== reviewRevision || !isJsonObject(next.settings))
        throw new ExtensionGrantInvalid();
      return next.settings;
    },
    async patchConfig(settings, signal) {
      // The original grant selects module-global versus apps.<app>.<module>.
      // Neither the app nor a config path is accepted in this request.
      await bound(() =>
        client.updateModuleConfig({ moduleId, settings }, { signal, headers: header }),
      );
    },
    async runAction(action, args, signal) {
      return await bound(() =>
        collectExtensionAction(signal, (actionSignal) =>
          client.runModuleAction(
            { moduleId, actionId: action, args },
            { signal: actionSignal, headers: header },
          ),
        ),
      );
    },
    async proxyFetch(service, path, options, signal) {
      const endpoint = `${agentOrigin}/api/v1/modules/${encodeURIComponent(moduleId)}/services/${encodeURIComponent(service)}/proxy${path}`;
      const headers = new Headers(options.headers);
      headers.set("Authorization", `Bearer ${token}`);
      headers.set("X-Stackpanel-Project", projectId);
      headers.set(grantHeader, grant);
      const response = await bound(() =>
        fetchWithAgentIdentity(agentOrigin, token, endpoint, {
          headers,
          signal,
          method: options.method ?? "GET",
          body: options.body,
          credentials: "omit",
          redirect: "error",
          cache: "no-store",
          referrerPolicy: "no-referrer",
        }),
      );
      if (
        (response.status === 401 || response.status === 403) &&
        response.headers.get("X-Stackpanel-Service-Response") !== "1"
      ) {
        await response.body?.cancel();
        throw new ExtensionGrantInvalid();
      }
      return await readProxyResult(response);
    },
    toast: (message) => {
      toast.message(moduleId, { description: message });
    },
  };
  const nonce = bridgeNonce();
  asset.hash = `stackpanel-bridge=${nonce}`;
  return {
    url: asset.href,
    source,
    nonce,
    authority,
    ops,
  };
}
