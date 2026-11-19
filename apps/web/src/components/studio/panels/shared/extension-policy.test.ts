import type { ExtensionCall, Permission } from "@stackpanel/extension-sdk/protocol";
import { describe, expect, it, vi } from "vite-plus/test";
import {
  dispatchExtensionCall,
  type ExtensionAuthority,
  ExtensionDenied,
  ExtensionGrantInvalid,
  type FrameOperations,
} from "./extension-policy";

const grants: Permission[] = ["config:read", "config:patch", "actions:run", "service:proxy"];
const read = { method: "getConfig" } satisfies ExtensionCall;
const patch = {
  method: "patchModuleConfig",
  settings: { view: { columns: ["name", "region"], pinned: false } },
} satisfies ExtensionCall;
const action = {
  method: "runAction",
  action: "refresh",
  args: { force: true },
} satisfies ExtensionCall;
const proxy = {
  method: "proxyFetch",
  service: "dashboard",
  path: "/v1/status.json",
  options: {},
} satisfies ExtensionCall;

function fixture(permissions = grants, appId?: string) {
  const authority: ExtensionAuthority = {
    projectId: "example-project",
    expiresAt: Date.now() + 120_000,
    context: { moduleId: "sample", panelId: "overview", permissions, appId },
    actions: new Map([
      [
        "refresh",
        {
          confirm: "Refresh this module?",
          argsSchema: { properties: { force: { type: "boolean" } } },
        },
      ],
      ["status", {}],
    ]),
    services: new Set(["dashboard"]),
  };
  const ops = {
    readConfig: vi.fn<FrameOperations["readConfig"]>().mockResolvedValue({ region: "west" }),
    patchConfig: vi.fn<FrameOperations["patchConfig"]>().mockResolvedValue(undefined),
    runAction: vi
      .fn<FrameOperations["runAction"]>()
      .mockResolvedValue({ stdout: "ok", stderr: "", exitCode: 0 }),
    proxyFetch: vi
      .fn<FrameOperations["proxyFetch"]>()
      .mockResolvedValue({ status: 200, body: "ok", contentType: "text/plain" }),
    confirm: vi.fn<FrameOperations["confirm"]>().mockResolvedValue(true),
    toast: vi.fn<FrameOperations["toast"]>(),
  } satisfies FrameOperations;
  const controller = new AbortController();
  const signal = controller.signal;
  const call = (raw: unknown) => dispatchExtensionCall(raw, authority, ops, signal);
  return { authority, ops, controller, signal, call };
}

describe("scoped extension calls", () => {
  it("exposes public context without granting config access", async () => {
    const { call, ops, authority } = fixture([], "web");
    Object.assign(authority.context, { privateMetadata: true });
    await expect(call({ method: "getContext" })).resolves.toEqual({
      moduleId: "sample",
      panelId: "overview",
      appId: "web",
      permissions: [],
    });
    await call({ method: "toast", message: "Ready" });
    expect(ops.toast).toHaveBeenCalledWith("Ready");
    expect(ops.readConfig).not.toHaveBeenCalled();
  });

  it("passes only relative settings and the host signal to config operations", async () => {
    const { call, ops, signal } = fixture(["config:read", "config:patch"]);
    await expect(call(read)).resolves.toEqual({ region: "west" });
    expect(ops.readConfig).toHaveBeenCalledWith(signal);
    await expect(call(patch)).resolves.toBeUndefined();
    expect(ops.patchConfig).toHaveBeenCalledWith(patch.settings, signal);
  });

  it("shows the authoritative targets, arguments and module's note separately", async () => {
    const { call, ops, signal } = fixture(["actions:run"], "web");
    await call({ method: "runAction", action: "status", args: {} });
    expect(ops.confirm.mock.calls[0]?.[0]).toContain('Action: "status"');
    expect(ops.confirm.mock.calls[0]?.[0]).not.toContain("Module-provided note");
    await expect(call(action)).resolves.toEqual({ stdout: "ok", stderr: "", exitCode: 0 });
    const [prompt] = ops.confirm.mock.calls[1]!;
    expect(prompt.split("\n")).toEqual(
      expect.arrayContaining([
        'Project: "example-project"',
        'Module: "sample"',
        'Panel: "overview"',
        'App: "web"',
        'Action: "refresh"',
        'Arguments: {"force": true}',
        'Module-provided note: "Refresh this module?"',
        "Once started, cancelling does not roll back changes.",
      ]),
    );
    expect(ops.runAction).toHaveBeenLastCalledWith("refresh", { force: true }, signal);
  });

  it("forwards only allowed request options to the evaluated service", async () => {
    const { call, ops, signal } = fixture(["service:proxy"], "web");
    await call({ ...proxy, path: "/" });
    expect(ops.proxyFetch).toHaveBeenLastCalledWith("dashboard", "/", {}, signal);
    expect(ops.confirm.mock.calls[0]?.[0]).toContain("Method: GET");
    expect(ops.confirm.mock.calls[0]?.[0]).toContain("Body: none");
    const options = {
      method: "POST",
      headers: { "Content-Type": "text/plain", Accept: "private-header" },
      body: "private-body",
    };
    await expect(call({ ...proxy, options })).resolves.toEqual({
      status: 200,
      body: "ok",
      contentType: "text/plain",
    });
    const [prompt] = ops.confirm.mock.calls[1]!;
    expect(prompt).not.toMatch(/private-(body|header)/);
    expect(prompt.split("\n")).toEqual(
      expect.arrayContaining([
        'Project: "example-project"',
        'Module: "sample"',
        'Panel: "overview"',
        'App: "web"',
        "Method: POST",
        'Service: "dashboard"',
        "Path: /v1/status.json",
        "Body: present (not shown)",
      ]),
    );
    expect(ops.proxyFetch).toHaveBeenLastCalledWith(
      "dashboard",
      "/v1/status.json",
      {
        method: "POST",
        headers: { "content-type": "text/plain", accept: "private-header" },
        body: "private-body",
      },
      signal,
    );
  });

  it.each([
    ["config:read", read],
    ["config:patch", patch],
    ["actions:run", action],
    ["service:proxy", proxy],
  ] as const)(
    "requires the specific %s grant before prompting or dispatch",
    async (missing, request) => {
      const { call, ops } = fixture(grants.filter((grant) => grant !== missing));
      await expect(call(request)).rejects.toBeInstanceOf(ExtensionDenied);
      for (const operation of Object.values(ops)) expect(operation).not.toHaveBeenCalled();
    },
  );

  it("forwards only relative settings for the host-bound app", async () => {
    const { call, ops, signal } = fixture(["config:patch"], "web");
    const change = { method: "patchModuleConfig", settings: { workers: 3 } };
    for (const override of [
      { appId: "other" },
      { configPath: "apps.other" },
      { moduleId: "other" },
    ]) {
      await expect(call({ ...change, ...override })).rejects.toBeInstanceOf(ExtensionDenied);
    }
    await expect(
      call({ ...change, settings: { "apps.other.sample.workers": 3 } }),
    ).rejects.toBeInstanceOf(ExtensionDenied);
    expect(ops.patchConfig).not.toHaveBeenCalled();
    await call(change);
    expect(ops.patchConfig).toHaveBeenCalledWith({ workers: 3 }, signal);
  });

  it("stops if the host user declines confirmation", async () => {
    const { call, ops } = fixture();
    ops.confirm.mockResolvedValue(false);
    await expect(call(action)).rejects.toBeInstanceOf(ExtensionDenied);
    expect(ops.confirm).toHaveBeenCalledOnce();
    expect(ops.runAction).not.toHaveBeenCalled();
  });

  it("reviews identical reads individually and never dispatches a declined request", async () => {
    const { call, ops } = fixture();
    await call(proxy);
    ops.confirm.mockResolvedValueOnce(false);
    await expect(call(proxy)).rejects.toBeInstanceOf(ExtensionDenied);
    expect(ops.confirm).toHaveBeenCalledTimes(2);
    expect(ops.proxyFetch).toHaveBeenCalledTimes(1);
  });

  it.each([proxy, action])(
    "rejects late approval after cancellation of $method",
    async (request) => {
      const { call, ops, controller } = fixture();
      const decision = Promise.withResolvers<boolean>();
      ops.confirm.mockReturnValueOnce(decision.promise);
      const result = call(request);
      expect(ops.confirm).toHaveBeenCalledOnce();
      controller.abort();
      decision.resolve(true);
      await expect(result).rejects.toMatchObject({ name: "AbortError" });
      expect(ops.proxyFetch).not.toHaveBeenCalled();
      expect(ops.runAction).not.toHaveBeenCalled();
    },
  );

  it.each(["grant", "request"])(
    "refuses approval after a suspended tab passes its %s deadline",
    async (kind) => {
      const { signal, ops, authority } = fixture();
      const deadline = Date.now() + 30_000;
      const clock = vi.spyOn(Date, "now");
      try {
        ops.confirm.mockImplementationOnce(async () => {
          clock.mockReturnValue(kind === "grant" ? authority.expiresAt : deadline);
          return true;
        });
        await expect(
          dispatchExtensionCall(proxy, authority, ops, signal, deadline),
        ).rejects.toBeInstanceOf(kind === "grant" ? ExtensionGrantInvalid : ExtensionDenied);
        expect(ops.proxyFetch).not.toHaveBeenCalled();
      } finally {
        clock.mockRestore();
      }
    },
  );

  it("cannot approve an action with a blank confirmation prompt", async () => {
    const { authority, ops, signal } = fixture();
    const actions = new Map([["refresh", { confirm: "  " }]]);
    await expect(
      dispatchExtensionCall(action, { ...authority, actions }, ops, signal),
    ).rejects.toBeInstanceOf(ExtensionDenied);
    expect(ops.confirm).not.toHaveBeenCalled();
    expect(ops.runAction).not.toHaveBeenCalled();
  });

  it("redacts schema-marked and secret-named arguments without changing the submitted values", async () => {
    const { authority, ops, signal } = fixture();
    const argsSchema = {
      properties: {
        entries: {
          items: {
            properties: {
              region: { type: "string" },
              api_key: { type: "string" },
              data: { writeOnly: true },
              passcode: { format: "password" },
              other: { "x-sensitive": true },
            },
          },
        },
      },
    };
    const actions = new Map([["refresh", { confirm: "Review\nApp: other", argsSchema }]]);
    const args = {
      entries: [
        {
          region: 'west"\nModule: other\u202e',
          api_key: "sample-one",
          data: "sample-two",
          passcode: "sample-three",
          other: "sample-four",
        },
      ],
    };
    await dispatchExtensionCall({ ...action, args }, { ...authority, actions }, ops, signal);
    const [prompt] = ops.confirm.mock.calls[0]!;
    expect(prompt).not.toMatch(/sample-(one|two|three|four)|\u202e/);
    expect(prompt.match(/\[redacted\]/g)).toHaveLength(4);
    expect(prompt).toContain('"west\\"\\nModule: other\\u202e"');
    expect(prompt).toContain('Module-provided note: "Review\\nApp: other"');
    expect(ops.runAction).toHaveBeenCalledWith("refresh", args, signal);
  });

  it("refuses ambiguous, undeclared and oversized confirmation details without prompting", async () => {
    const { authority, ops, signal, call } = fixture();
    await expect(call({ ...action, args: { extra: "unknown" } })).rejects.toBeInstanceOf(
      ExtensionDenied,
    );
    const actions = new Map([["refresh", { confirm: "Review", argsSchema: { oneOf: [{}] } }]]);
    await expect(
      dispatchExtensionCall(action, { ...authority, actions }, ops, signal),
    ).rejects.toBeInstanceOf(ExtensionDenied);
    await expect(call({ ...action, args: { force: "a".repeat(1500) } })).rejects.toBeInstanceOf(
      ExtensionDenied,
    );
    expect(ops.confirm).not.toHaveBeenCalled();
    expect(ops.runAction).not.toHaveBeenCalled();
  });

  it.each([action, proxy])(
    "does not review $method with incomplete or expired authority",
    async (request) => {
      const { authority, ops, signal } = fixture();
      for (const invalid of [
        { ...authority, projectId: "" },
        { ...authority, context: { ...authority.context, panelId: "" } },
        { ...authority, expiresAt: Date.now() - 1 },
      ]) {
        await expect(dispatchExtensionCall(request, invalid, ops, signal)).rejects.toBeInstanceOf(
          ExtensionGrantInvalid,
        );
      }
      expect(ops.confirm).not.toHaveBeenCalled();
      expect(ops.runAction).not.toHaveBeenCalled();
      expect(ops.proxyFetch).not.toHaveBeenCalled();
    },
  );

  it("does not dispatch after the host revokes the session", async () => {
    const { call, ops, controller } = fixture();
    controller.abort();
    await expect(call(action)).rejects.toMatchObject({ name: "AbortError" });
    await expect(call(proxy)).rejects.toMatchObject({ name: "AbortError" });
    expect(ops.proxyFetch).not.toHaveBeenCalled();
    expect(ops.confirm).not.toHaveBeenCalled();
    expect(ops.runAction).not.toHaveBeenCalled();
  });

  it("leaves non-policy errors for the host's generic error handler", async () => {
    const { call, ops } = fixture();
    const failure = new Error("Backend failed");
    ops.readConfig.mockRejectedValue(failure);
    await expect(call(read)).rejects.toBe(failure);
  });
});

describe("untrusted extension input", () => {
  it.each([
    ["module override", { ...read, moduleId: "other" }],
    ["config path override", { ...patch, configPath: "other" }],
    ["permission override", { method: "getContext", permissions: grants }],
    ["action owned elsewhere", { ...action, action: "elsewhere" }],
    ["confirmation override", { ...action, confirm: false }],
    ["service owned elsewhere", { ...proxy, service: "private" }],
    ["missing options", { method: "proxyFetch", service: "dashboard", path: "/" }],
    ["missing args", { method: "runAction", action: "refresh" }],
    ["empty toast", { method: "toast", message: " " }],
    ["unknown method", { method: "readProject" }],
    ["non-object", null],
  ])("denies %s without invoking a host operation", async (_label, request) => {
    const { call, ops } = fixture();
    await expect(call(request)).rejects.toBeInstanceOf(ExtensionDenied);
    for (const operation of Object.values(ops)) expect(operation).not.toHaveBeenCalled();
  });

  it.each([
    "__proto__",
    "constructor",
    "prototype",
    "stackpanel",
    "apps",
    "a.b",
    "a/b",
    "/root",
    "a\\b",
  ])("rejects nested config key %s even inside arrays", async (key) => {
    const { call, ops } = fixture();
    await expect(call({ ...patch, settings: { items: [{ [key]: null }] } })).rejects.toBeInstanceOf(
      ExtensionDenied,
    );
    expect(ops.patchConfig).not.toHaveBeenCalled();
  });

  it("requires bounded plain JSON arguments before prompting", async () => {
    const { call, ops } = fixture();
    const cyclic: Record<string, unknown> = {};
    cyclic.self = cyclic;
    let deep: unknown = 1;
    for (let i = 0; i < 20; i++) deep = [deep];
    const invalid = [
      [],
      { value: new Date() },
      { value: undefined },
      { value: NaN },
      { list: Array(3) },
      { value: deep },
      cyclic,
      { large: Array(5000).fill(1) },
      { large: "a".repeat(40_000), more: "b".repeat(40_000) },
      { nested: { constructor: "data" } },
    ];
    for (const args of invalid)
      await expect(call({ ...action, args })).rejects.toBeInstanceOf(ExtensionDenied);
    expect(ops.confirm).not.toHaveBeenCalled();
    expect(ops.runAction).not.toHaveBeenCalled();
  });

  it("rejects accessor properties without reading them", async () => {
    const { call, ops } = fixture();
    const getter = vi.fn(() => 1);
    const settings = Object.defineProperty({}, "region", { enumerable: true, get: getter });
    await expect(call({ ...patch, settings })).rejects.toBeInstanceOf(ExtensionDenied);
    expect(getter).not.toHaveBeenCalled();
    expect(ops.patchConfig).not.toHaveBeenCalled();
  });

  it.each([
    "relative",
    "//example.test",
    "https://example.test",
    "/../item",
    "/a/./b",
    "/a//b",
    "/%252e",
    "/a\\b",
    "/a?b=c",
    "/a#b",
  ])("rejects nonliteral service path %s", async (path) => {
    const { call, ops } = fixture();
    await expect(call({ ...proxy, path })).rejects.toBeInstanceOf(ExtensionDenied);
    expect(ops.confirm).not.toHaveBeenCalled();
    expect(ops.proxyFetch).not.toHaveBeenCalled();
  });

  it.each([
    ["authorization", { headers: { Authorization: "sample" } }],
    ["cookie", { headers: { cookie: "sample" } }],
    ["agent token", { headers: { "X-Stackpanel-Token": "sample" } }],
    ["duplicate header", { headers: { Accept: "text/plain", accept: "application/json" } }],
    ["multiline header", { headers: { accept: "text/\nplain" } }],
    ["credentials", { credentials: "include" }],
    ["unsupported method", { method: "CONNECT" }],
    ["GET body", { method: "GET", body: "text" }],
    ["implicit GET body", { body: "text" }],
    ["non-text body", { method: "POST", body: {} }],
    ["oversized body", { method: "POST", body: "a".repeat(65_537) }],
  ])("rejects proxy option: %s", async (_label, options) => {
    const { call, ops } = fixture();
    await expect(call({ ...proxy, options })).rejects.toBeInstanceOf(ExtensionDenied);
    expect(ops.confirm).not.toHaveBeenCalled();
    expect(ops.proxyFetch).not.toHaveBeenCalled();
  });
});
