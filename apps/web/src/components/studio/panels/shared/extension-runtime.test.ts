import type { JsonObject } from "@bufbuild/protobuf";
import {
  Code,
  ConnectError,
  createClient,
  createRouterTransport,
  type HandlerContext,
} from "@connectrpc/connect";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import type { Permission } from "@stackpanel/extension-sdk/protocol";
import { expect, it, vi } from "vite-plus/test";
import { dispatchExtensionCall, ExtensionGrantInvalid } from "./extension-policy";
import { collectExtensionAction } from "./extension-action-stream";
import { openExtension } from "./extension-runtime";

vi.mock("@/lib/agent-identity", () => ({
  fetchWithAgentIdentity: (_origin: string, _token: string, url: string, init: RequestInit) =>
    fetch(url, init),
}));

const reviewRevision = "a".repeat(64);

async function launch(
  permissions: Permission[],
  appId?: string,
  issue = true,
  echo = reviewRevision,
) {
  const scope = { moduleId: "sample", panelId: "custom", projectId: "foo", appId };
  const revision = { current: "original" };
  const refresh: { reviewRevision: string; settings?: JsonObject } = {
    reviewRevision,
    settings: appId === undefined ? { region: "west" } : { workers: 2 },
  };
  const writes = vi.fn();
  const actions = vi.fn();
  const received: (string | null)[] = [];
  let opens = 0;
  function requireOriginal(ctx: HandlerContext) {
    const value = ctx.requestHeader.get("X-Stackpanel-UI-Grant");
    received.push(value);
    if (value !== revision.current)
      throw new ConnectError("Revision changed", Code.PermissionDenied);
  }
  const client = createClient(
    ModuleService,
    createRouterTransport((router) =>
      router.service(ModuleService, {
        openModuleUI(req, ctx) {
          if (
            req.moduleId !== scope.moduleId ||
            req.panelId !== scope.panelId ||
            req.appId !== (appId ?? "")
          )
            throw new Error("Invalid document target");
          if (req.reviewRevision !== (opens ? "" : reviewRevision))
            throw new Error("Invalid reviewed revision");
          if (opens++) requireOriginal(ctx);
          if (issue)
            ctx.responseHeader.set(
              "X-Stackpanel-UI-Grant",
              opens === 1 ? "original" : "do-not-renew",
            );
          ctx.responseHeader.set(
            "X-Stackpanel-UI-Expires-At",
            String(Math.floor(Date.now() / 1000) + 90),
          );
          return {
            reviewRevision: opens === 1 ? echo : refresh.reviewRevision,
            url:
              opens === 1
                ? `/api/v1/modules/sample/ui/custom/_ticket/${"a".repeat(80)}/index.html`
                : "",
            settings: permissions.includes("config:read") ? refresh.settings : undefined,
            permissions,
            actionIds: permissions.includes("actions:run") ? ["status"] : [],
            actions: permissions.includes("actions:run")
              ? {
                  status: { label: "Status", argsSchema: { type: "object" }, outputMode: "stream" },
                }
              : undefined,
          };
        },
        updateModuleConfig(req, ctx) {
          requireOriginal(ctx);
          if (appId) {
            if (
              typeof req.settings?.workers !== "number" ||
              Object.keys(req.settings).length !== 1
            ) {
              throw new ConnectError("Field not public", Code.PermissionDenied);
            }
            refresh.settings = { workers: req.settings.workers };
          }
          writes(req);
          return { message: "saved" };
        },
        async *runModuleAction(req, ctx) {
          requireOriginal(ctx);
          actions(req.actionId);
          yield { event: { case: "exitCode", value: 0 } };
        },
        getModuleOutputs: () => ({
          outputs: {
            moduleId: "sample",
            services: [
              { name: "cache", proxyEnabled: true },
              { name: "db", proxyEnabled: false },
            ],
          },
        }),
      }),
    ),
  );
  const signal = new AbortController().signal;
  const { authority, ops, url } = await openExtension(
    {
      ...scope,
      reviewRevision,
      agentOrigin: "http://localhost:9876",
      client,
      token: "parent-only",
    },
    {
      projectId: scope.projectId,
      context: { ...scope, permissions },
      source: { kind: "bundle", origin: "http://localhost:9876" },
    },
    signal,
  );
  const confirm = vi.fn(async (_message: string, _signal: AbortSignal) => true);
  return {
    dispatch: (call: unknown) =>
      dispatchExtensionCall(call, authority, { ...ops, confirm }, signal),
    confirm,
    writes,
    actions,
    revision,
    refresh,
    received,
    url,
  };
}

it.each(["", "b".repeat(64)])("refuses a missing or changed review echo", async (echo) => {
  await expect(launch(["service:proxy"], undefined, true, echo)).rejects.toThrow(
    ExtensionGrantInvalid,
  );
});

it("never falls back to bearer-only dispatch for module or app writes", async () => {
  await expect(launch([], undefined, false)).rejects.toThrow(/valid UI grant/);
  await expect(launch(["config:patch"], "storefront", false)).rejects.toThrow(/valid UI grant/);
});

it("writes relative settings with the original grant, and cannot reuse it after a revision change", async () => {
  const { dispatch, writes, revision, received, url } = await launch(["config:patch"]);
  const call = { method: "patchModuleConfig", settings: { region: "west" } };
  await dispatch(call);
  expect(writes).toHaveBeenCalledWith(
    expect.objectContaining({ moduleId: "sample", settings: { region: "west" } }),
  );
  revision.current = "new-evaluation";
  await expect(dispatch(call)).rejects.toThrow(ExtensionGrantInvalid);
  expect(writes).toHaveBeenCalledTimes(1);
  expect(received).toEqual(["original", "original"]);
  expect(url).not.toContain("original");
});

it("reads module settings with the document grant and without exposing host-only data", async () => {
  const { dispatch, received } = await launch(["config:read"]);
  expect(await dispatch({ method: "getContext" })).toEqual({
    moduleId: "sample",
    panelId: "custom",
    permissions: ["config:read"],
  });
  expect(await dispatch({ method: "getConfig" })).toEqual({ region: "west" });
  expect(received).toEqual(["original"]);
});

it("app reads do not swap the original grant for one minted by a later lookup", async () => {
  const { dispatch, writes, received } = await launch(["config:read"], "storefront");
  expect(await dispatch({ method: "getConfig" })).toEqual({ workers: 2 });
  expect(await dispatch({ method: "getConfig" })).toEqual({ workers: 2 });
  expect(received).toEqual(["original", "original"]);
  await expect(dispatch({ method: "patchModuleConfig", settings: { x: true } })).rejects.toThrow();
  expect(writes).not.toHaveBeenCalled();
});

it.each([undefined, "storefront"])(
  "rejects stale or incomplete settings reads for %s",
  async (appId) => {
    const { dispatch, refresh, received } = await launch(["config:read"], appId);
    refresh.settings = {};
    expect(await dispatch({ method: "getConfig" })).toEqual({});
    refresh.settings = undefined;
    await expect(dispatch({ method: "getConfig" })).rejects.toThrow(ExtensionGrantInvalid);
    refresh.settings = { fresh: true };
    for (const echo of ["", "b".repeat(64)]) {
      refresh.reviewRevision = echo;
      await expect(dispatch({ method: "getConfig" })).rejects.toThrow(ExtensionGrantInvalid);
    }
    expect(received).toEqual(Array(4).fill("original"));
  },
);

it("patches the grant-bound app and reads back its scoped settings without changing targets", async () => {
  const { dispatch, writes, received } = await launch(
    ["config:read", "config:patch"],
    "storefront",
  );
  const call = { method: "patchModuleConfig", settings: { workers: 4 } };
  await dispatch(call);
  expect(writes.mock.calls[0]?.[0]).toEqual({
    $typeName: "stackpanel.agent.v1.UpdateModuleConfigRequest",
    moduleId: "sample",
    settings: { workers: 4 },
  });
  expect(await dispatch({ method: "getConfig" })).toEqual({ workers: 4 });
  expect(received).toEqual(["original", "original"]);
  await expect(dispatch({ ...call, settings: { other: true } })).rejects.toThrow(
    ExtensionGrantInvalid,
  );
  expect(writes).toHaveBeenCalledTimes(1);
});

it("requires host review even for an allowed action without a module-provided note", async () => {
  const { dispatch, actions, received, confirm } = await launch(["actions:run"]);
  const call = { method: "runAction", action: "status", args: {} };
  await expect(dispatch({ ...call, action: "deploy" })).rejects.toThrow(/not allowed/i);
  expect(confirm).not.toHaveBeenCalled();
  confirm.mockResolvedValueOnce(false);
  await expect(dispatch(call)).rejects.toThrow(/not confirmed/i);
  expect(actions).not.toHaveBeenCalled();
  expect(await dispatch(call)).toMatchObject({ exitCode: 0 });
  expect(received).toEqual(["original"]);
  expect(actions.mock.calls).toEqual([["status"]]);
});

it("aborts the action transport on output overflow before closing its iterator", async () => {
  let abortedBeforeClose = false;
  const result = collectExtensionAction(new AbortController().signal, async function* (signal) {
    try {
      yield {
        $typeName: "stackpanel.agent.v1.RunModuleActionResponse",
        event: { case: "stdout", value: "x".repeat(1024 * 1024 + 1) },
      };
    } finally {
      abortedBeforeClose = signal.aborted;
    }
  });
  await expect(result).rejects.toThrow(/output exceeds/i);
  expect(abortedBeforeClose).toBe(true);
});

it("relays a service denial without revoking the document's other grants", async () => {
  const { dispatch } = await launch(["service:proxy", "config:read"]);
  vi.mocked(globalThis.fetch).mockResolvedValueOnce(
    new Response("Sign in to this service", {
      status: 403,
      headers: { "X-Stackpanel-Service-Response": "1", "Content-Type": "text/plain" },
    }),
  );
  expect(
    await dispatch({ method: "proxyFetch", service: "cache", path: "/info", options: {} }),
  ).toEqual({ status: 403, body: "Sign in to this service", contentType: "text/plain" });
  expect(await dispatch({ method: "getConfig" })).toEqual({ region: "west" });
});

it("sends credentials and grant only to the pinned proxy, without exposing headers or following redirects", async () => {
  const { dispatch, confirm } = await launch(["service:proxy"]);
  const call = { method: "proxyFetch", service: "cache", path: "/info", options: {} };
  const fetch = vi.mocked(globalThis.fetch);
  fetch.mockResolvedValueOnce(
    new Response("ok", { headers: { "content-type": "text/plain", "x-private": "hidden" } }),
  );
  await expect(dispatch({ ...call, service: "db" })).rejects.toThrow();
  expect(confirm).not.toHaveBeenCalled();
  confirm.mockResolvedValueOnce(false);
  await expect(dispatch(call)).rejects.toThrow(/not approved/i);
  expect(fetch).not.toHaveBeenCalled();
  expect(await dispatch(call)).toEqual({ status: 200, body: "ok", contentType: "text/plain" });
  const [url, init] = fetch.mock.calls[0]!;
  expect(url).toBe("http://localhost:9876/api/v1/modules/sample/services/cache/proxy/info");
  expect(init).toMatchObject({
    credentials: "omit",
    redirect: "error",
    referrerPolicy: "no-referrer",
  });
  expect(new Headers(init?.headers).get("Authorization")).toBe("Bearer parent-only");
  expect(new Headers(init?.headers).get("X-Stackpanel-Project")).toBe("foo");
  expect(new Headers(init?.headers).get("X-Stackpanel-UI-Grant")).toBe("original");
  fetch.mockResolvedValueOnce(
    new Response(null, { status: 302, headers: { location: "http://localhost:9876/" } }),
  );
  await expect(dispatch(call)).rejects.toThrow();
  fetch.mockResolvedValueOnce(new Response(null, { status: 403 }));
  await expect(dispatch(call)).rejects.toThrow(ExtensionGrantInvalid);
});
