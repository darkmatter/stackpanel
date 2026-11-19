// @vitest-environment jsdom
import { MessageChannel as NodeMessageChannel } from "node:worker_threads";
import { createExtensionClient } from "@stackpanel/extension-sdk";
import {
  ACTION_TIMEOUT_MS,
  type ActionResult,
  type Permission,
} from "@stackpanel/extension-sdk/protocol";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { bindExtensionFrame } from "./extension-session";
import { ExtensionGrantInvalid, type ExtensionOperations } from "./extension-policy";
import { extensionFrameUrl } from "./extension-url";
import { SandboxedCustomPanel } from "./sandboxed-custom-panel";
import type { NixPanel } from "./panel-types";

const agent = vi.hoisted(() => ({
  identity: {
    selectedProjectId: "project-a" as string | null,
    host: "localhost",
    port: 9876,
    token: "host-credential",
    isAuthenticated: true,
  },
  links: new Map<string, string>(),
  client: { getModuleOutputs: vi.fn(), openModuleUI: vi.fn(), runModuleAction: vi.fn() },
}));
vi.mock("@/lib/agent-provider", () => ({
  useAgentContext: () => agent.identity,
  useModuleServiceClient: () => agent.client,
}));
vi.mock("@/lib/agent-sse-provider", () => ({ useAgentSSEOptional: () => null }));
vi.mock("../../extension-dev-toolbar", () => ({
  useExtensionDevTools: () =>
    agent.links.size ? { links: agent.links, revision: new Map() } : null,
}));

const nonce = "1".repeat(32);
const asset = `/api/v1/modules/sample/ui/custom/_ticket/${"a".repeat(240)}/index.html`;
const reviewRevision = "1".repeat(64);
const panel: NixPanel = {
  module: "sample",
  id: "custom",
  enabled: true,
  type: "PANEL_TYPE_CUSTOM",
  slot: "module",
  fields: [],
  apps: {},
  title: "Dashboard",
  order: 0,
  uiReview: { revision: reviewRevision },
  uiBundle: { package: "/nix/store/example", entry: "index.html", permissions: ["actions:run"] },
};
const cleanups: Array<() => void> = [];
afterEach(() => {
  while (cleanups.length) cleanups.pop()?.();
  agent.identity.selectedProjectId = "project-a";
  agent.identity.token = "host-credential";
  agent.links.clear();
});

function discovery(data: unknown, source: Window, ports: MessagePort[], origin = "null") {
  // jsdom does not implement transfers between documents. Supply only the
  // browser's delivery metadata; RPC below uses real entangled MessagePorts.
  window.dispatchEvent(Object.assign(new Event("message"), { data, source, ports, origin }));
}

function harness(permissions: Permission[]) {
  const frame = document.createElement("iframe");
  const parent = {
    postMessage: (data: unknown, _origin: string, ports: MessagePort[]) =>
      discovery(data, child, ports),
  };
  const child = Object.assign(new EventTarget(), {
    parent,
    location: { hash: `#stackpanel-bridge=${nonce}` },
    document: document.implementation.createHTMLDocument(),
    setTimeout: window.setTimeout.bind(window),
    clearTimeout: window.clearTimeout.bind(window),
    MessageChannel: NodeMessageChannel,
    postMessage: (data: unknown) =>
      child.dispatchEvent(Object.assign(new Event("message"), { source: parent, data })),
  }) as unknown as Window;
  // Stand-in for the browsing context: DOM navigation is controlled by each test.
  Object.defineProperties(frame, { contentWindow: { value: child }, isConnected: { value: true } });
  const ops = {
    readConfig: vi.fn(async () => ({ region: "west" })),
    patchConfig: vi.fn(async () => {}),
    runAction: vi
      .fn<ExtensionOperations["runAction"]>()
      .mockResolvedValue({ exitCode: 0, stdout: "ok", stderr: "" }),
    proxyFetch: vi.fn(async () => ({ body: "ok", status: 200, contentType: "text/plain" })),
    toast: vi.fn(),
    confirm: vi.fn(async () => true),
  };
  const navigated = vi.fn();
  const audit = vi.fn();
  const context = { moduleId: "sample", panelId: "custom", permissions };
  const session = bindExtensionFrame(
    frame,
    nonce,
    {
      projectId: "test-project",
      expiresAt: Date.now() + 600_000,
      context,
      actions: new Map([["refresh", {}]]),
      services: new Set(["cache"]),
    },
    ops,
    audit,
    navigated,
  );
  cleanups.push(session.dispose);
  return { child, frame, ops, audit, context, navigated, session };
}

function recordingPort() {
  return Object.assign(new EventTarget(), {
    onmessage: null as ((e: MessageEvent) => Promise<void>) | null,
    postMessage: vi.fn(),
    close: vi.fn(),
  });
}

it("runs the vanilla SDK over an acknowledged document port; mirrors theme and scoped config", async () => {
  const { child, frame, ops, audit, context } = harness([
    "config:read",
    "config:patch",
    "actions:run",
    "service:proxy",
  ]);
  document.documentElement.style.setProperty("--background", "#181818");
  cleanups.push(() => {
    document.documentElement.style.removeProperty("--background");
  });
  const sdk = createExtensionClient(child); // Offer before load; the hello must recover it.
  cleanups.push(sdk.dispose);
  const pendingContext = sdk.getContext();
  frame.dispatchEvent(new Event("load"));
  await expect(pendingContext).resolves.toEqual(context);
  expect(child.document.documentElement.style.getPropertyValue("--background")).toBe("#181818");
  await expect(sdk.getConfig()).resolves.toEqual({ region: "west" });
  const changed = vi.fn();
  sdk.onConfigChange(changed);
  await sdk.patchModuleConfig({ region: "west" });
  await waitFor(() => expect(changed).toHaveBeenCalledWith({ region: "west" }));
  await expect(sdk.runAction("elsewhere")).rejects.toThrow();
  await expect(sdk.proxyFetch("other", "/")).rejects.toThrow();
  expect(ops.runAction).not.toHaveBeenCalled();
  expect(ops.proxyFetch).not.toHaveBeenCalled();
  expect(audit).toHaveBeenCalledWith(
    expect.objectContaining({ method: "runAction", outcome: "denied" }),
  );
});

it("does not publish config to a write-only SDK or reveal backend error details", async () => {
  const { child, frame, ops } = harness(["config:patch"]);
  frame.dispatchEvent(new Event("load"));
  const sdk = createExtensionClient(child);
  cleanups.push(sdk.dispose);
  const changed = vi.fn();
  sdk.onConfigChange(changed);
  await sdk.patchModuleConfig({ mode: "auto" });
  await expect(sdk.getConfig()).rejects.toThrow();
  expect(ops.readConfig).not.toHaveBeenCalled();
  expect(changed).not.toHaveBeenCalled();
  ops.patchConfig.mockRejectedValue(new Error("sensitive transport details"));
  await expect(sdk.patchModuleConfig({ mode: "auto" })).rejects.toThrow(
    /^Extension operation failed$/,
  );
});

it("checks source, opaque origin and nonce; refuses replay, second bind, and navigation", async () => {
  const { child, frame, ops, navigated } = harness([]);
  const offer = { type: "stackpanel:ready", nonce };
  const badPort = { postMessage: vi.fn(), close: vi.fn() } as unknown as MessagePort;
  frame.dispatchEvent(new Event("load"));
  discovery(offer, window, [badPort]);
  discovery(offer, child, [badPort], "https://other.test");
  discovery({ ...offer, nonce: "0".repeat(32) }, child, [badPort]);
  expect(badPort.postMessage).not.toHaveBeenCalled();
  const port = recordingPort();
  discovery(offer, child, [port as unknown as MessagePort]);
  expect(port.postMessage).toHaveBeenCalledWith({ type: "connected" });
  discovery(offer, child, [badPort]);
  expect(badPort.postMessage).not.toHaveBeenCalled();
  const handle = port.onmessage!;
  const request = new MessageEvent("message", {
    data: { type: "request", id: 2, call: { method: "toast", message: "ok" } },
  });
  await handle(request);
  await handle(request);
  expect(ops.toast).toHaveBeenCalledTimes(1);
  frame.dispatchEvent(new Event("load"));
  expect(navigated).toHaveBeenCalledOnce();
  expect(port.close).toHaveBeenCalledOnce();
  await handle(new MessageEvent("message", { data: { ...request.data, id: 3 } }));
  discovery(offer, child, [badPort]);
  expect(ops.toast).toHaveBeenCalledTimes(1);
  expect(badPort.postMessage).not.toHaveBeenCalled();
});

it.each(["abort", "timeout", "dispose"])(
  "cancels a running host action on SDK %s",
  async (cause) => {
    const { child, frame, ops, context, audit } = harness(["actions:run"]);
    const started = Promise.withResolvers<AbortSignal>();
    const finish = Promise.withResolvers<ActionResult>();
    ops.runAction.mockImplementationOnce((_id, _args, signal) => {
      started.resolve(signal);
      return finish.promise;
    });
    frame.dispatchEvent(new Event("load"));
    const sdk = createExtensionClient(child);
    cleanups.push(sdk.dispose);
    const timers = vi.spyOn(child, "setTimeout");
    const controller = new AbortController();
    const action = sdk.runAction("refresh", {}, controller.signal);
    const hostSignal = await started.promise;
    const aborted = Promise.withResolvers<void>();
    hostSignal.addEventListener("abort", () => aborted.resolve(), { once: true });
    if (cause === "timeout") {
      // Advance just the child deadline; the independent host deadline has not fired.
      const callback = timers.mock.calls.find(([, delay]) => delay === ACTION_TIMEOUT_MS)?.[0];
      if (typeof callback !== "function") throw new Error("Missing action deadline");
      callback();
      await expect(action).rejects.toThrow("timed out");
    } else if (cause === "dispose") {
      sdk.dispose();
      await expect(action).rejects.toThrow("closed");
    } else {
      controller.abort();
      await expect(action).rejects.toMatchObject({ name: "AbortError" });
    }
    await aborted.promise;
    finish.resolve({ stdout: "late", stderr: "", exitCode: 0 });
    if (cause !== "dispose") await expect(sdk.getContext()).resolves.toEqual(context);
    expect(audit).not.toHaveBeenCalledWith(
      expect.objectContaining({ method: "runAction", outcome: "allowed" }),
    );
  },
);

it("drops a cancelled pre-handshake action instead of sending it after ready", async () => {
  const { child, frame, ops, context } = harness(["actions:run"]);
  const sdk = createExtensionClient(child);
  cleanups.push(sdk.dispose);
  const controller = new AbortController();
  const action = sdk.runAction("refresh", {}, controller.signal);
  controller.abort();
  await expect(action).rejects.toMatchObject({ name: "AbortError" });
  frame.dispatchEvent(new Event("load"));
  await expect(sdk.getContext()).resolves.toEqual(context);
  expect(ops.runAction).not.toHaveBeenCalled();
});

it("cancels only the named request and never forwards its late rejection", async () => {
  const { frame, child, ops } = harness(["actions:run"]);
  const port = recordingPort();
  frame.dispatchEvent(new Event("load"));
  discovery({ type: "stackpanel:ready", nonce }, child, [port as unknown as MessagePort]);
  const handle = port.onmessage!;
  const first = Promise.withResolvers<ActionResult>();
  const second = Promise.withResolvers<ActionResult>();
  ops.runAction.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
  const action = (id: number) =>
    handle(
      new MessageEvent("message", {
        data: {
          type: "request",
          id,
          call: { method: "runAction", action: "refresh", args: {} },
        },
      }),
    );
  const a = action(1);
  const b = action(2);
  await waitFor(() => expect(ops.runAction).toHaveBeenCalledTimes(2));
  await handle(new MessageEvent("message", { data: { type: "cancel", id: 1 } }));
  expect(ops.runAction.mock.calls.map(([, , signal]) => signal.aborted)).toEqual([true, false]);
  port.postMessage.mockClear();
  first.reject(new Error("late failure"));
  const value = { stdout: "done", stderr: "", exitCode: 0 };
  second.resolve(value);
  await Promise.all([a, b]);
  expect(port.postMessage.mock.calls).toEqual([[{ type: "result", id: 2, value }]]);
});

it.each(["deadline", "port close", "unmount", "grant change"])(
  "aborts host work on %s and suppresses late output",
  async (cause) => {
    vi.useFakeTimers();
    cleanups.push(() => {
      vi.useRealTimers();
    });
    const { frame, child, ops, navigated, session } = harness(["actions:run", "config:read"]);
    const port = recordingPort();
    frame.dispatchEvent(new Event("load"));
    discovery({ type: "stackpanel:ready", nonce }, child, [port as unknown as MessagePort]);
    const handle = port.onmessage!;
    const started = Promise.withResolvers<AbortSignal>();
    const finish = Promise.withResolvers<ActionResult>();
    ops.runAction.mockImplementation((_action, _args, signal) => {
      started.resolve(signal);
      return finish.promise;
    });
    const late = handle(
      new MessageEvent("message", {
        data: {
          type: "request",
          id: 1,
          call: { method: "runAction", action: "refresh", args: {} },
        },
      }),
    );
    const signal = await started.promise;
    expect(signal.aborted).toBe(false);
    if (cause === "deadline") {
      vi.advanceTimersByTime(ACTION_TIMEOUT_MS);
      expect(port.postMessage).toHaveBeenCalledWith({
        type: "error",
        id: 1,
        error: "Extension operation timed out",
      });
    } else if (cause === "grant change") {
      ops.readConfig.mockRejectedValue(new ExtensionGrantInvalid());
      await handle(
        new MessageEvent("message", {
          data: { type: "request", id: 2, call: { method: "getConfig" } },
        }),
      );
      expect(navigated).toHaveBeenCalledOnce();
      expect(port.postMessage).toHaveBeenCalledWith({
        type: "error",
        id: 2,
        error: "Extension grant is no longer valid",
      });
    } else if (cause === "port close") {
      port.dispatchEvent(new Event("close"));
    } else {
      session.dispose();
    }
    expect(signal.aborted).toBe(true);
    port.postMessage.mockClear();
    finish.resolve({ stdout: "late", stderr: "", exitCode: 0 });
    await late;
    expect(port.postMessage).not.toHaveBeenCalled();
  },
);

describe("iframe launch", () => {
  const launch = (url: string, devUrl = "") =>
    extensionFrameUrl("http://localhost:9876", "https://studio.test", "sample", "custom", {
      url,
      devUrl,
    });
  it("rejects non-ticket assets, traversal, foreign modules and non-development origins", () => {
    for (const url of [
      "https://other.test/a",
      asset.replace("/sample/", "/other/"),
      asset.replace("/custom/", "/other/"),
      asset.replace("index.html", "../other"),
      `${asset}?token=bad`,
    ])
      expect(() => launch(url)).toThrow();
    for (const url of [
      "https://example.test",
      "http://localhost:9876/pair",
      "http://user@localhost:8000",
      "http://localhost:8000/?token=bad",
    ])
      expect(() => launch(asset, url)).toThrow();
    expect(launch(asset).origin).toBe("http://localhost:9876");
    expect(launch(asset, "http://127.0.0.1:5173/").port).toBe("5173");
  });
  function issueDocument(
    devUrl = "",
    permissions: Permission[] = ["actions:run"],
    wait?: Promise<void>,
    response?: Record<string, unknown>,
  ) {
    agent.client.getModuleOutputs.mockResolvedValue({
      outputs: { moduleId: "sample", services: [{ name: "cache", proxyEnabled: true }] },
    });
    agent.client.openModuleUI.mockImplementation(async (input, options) => {
      options.onHeader(
        new Headers({
          "X-Stackpanel-UI-Grant": "fixture-binding",
          "X-Stackpanel-UI-Expires-At": String(Math.floor(Date.now() / 1000) + 120),
        }),
      );
      if (wait) await wait;
      return {
        url: asset,
        devUrl,
        reviewRevision: input.reviewRevision,
        permissions,
        actionIds: permissions.includes("actions:run") ? ["status"] : [],
        actions: permissions.includes("actions:run")
          ? {
              status: { label: "Status", argsSchema: { type: "object" }, outputMode: "stream" },
            }
          : {},
        ...response,
      };
    });
  }

  it("shows only the validated dev origin before opt-in; deny and stop discard the launch", async () => {
    const origin = "http://127.0.0.1:5173";
    // The toolbar is a separate snapshot and must not control a launch review.
    agent.links.set("sample", "http://127.0.0.1:5174/untrusted-hint");
    issueDocument(`${origin}/private-path`);
    const reviewedPanel = { ...panel, uiReview: { revision: reviewRevision, devOrigin: origin } };
    const view = render(<SandboxedCustomPanel panel={reviewedPanel} />);
    expect(await screen.findByText("Locally linked development server")).toBeTruthy();
    expect(screen.getByText(`Origin: ${origin}`)).toBeTruthy();
    expect(view.container.textContent).toContain("its own content security policy");
    expect(view.container.textContent).not.toContain("private-path");
    expect(view.container.querySelector("iframe")).toBeNull();
    expect(agent.client.openModuleUI).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Deny" }));
    expect(view.container.querySelector("iframe")).toBeNull();
    expect(agent.client.openModuleUI).not.toHaveBeenCalled();
    expect(globalThis.fetch).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Review panel" }));
    expect(agent.client.openModuleUI).not.toHaveBeenCalled();
    fireEvent.click(await screen.findByRole("button", { name: "Open panel once" }));
    const frame = await screen.findByTitle<HTMLIFrameElement>("Dashboard");
    expect(new URL(frame.src).origin).toBe(origin);
    fireEvent.click(screen.getByRole("button", { name: "Stop panel" }));
    expect(frame.isConnected).toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Review panel" }));
    expect(await screen.findByRole("button", { name: "Open panel once" })).toBeTruthy();
    expect(view.container.querySelector("iframe")).toBeNull();
    expect(agent.client.openModuleUI).toHaveBeenCalledTimes(1);
  });

  it.each([
    undefined,
    { revision: "" },
    { revision: "A".repeat(64) },
    { revision: reviewRevision, devOrigin: "https://example.test" },
  ])("does not offer a launch without a valid snapshot marker", (uiReview) => {
    render(<SandboxedCustomPanel panel={{ ...panel, uiReview }} />);
    expect(screen.getByRole("alert").textContent).toContain("Refresh the project");
    expect(screen.queryByRole("button", { name: "Open panel once" })).toBeNull();
    expect(agent.client.openModuleUI).not.toHaveBeenCalled();
  });

  it.each([undefined, null, "actions:run", ["unknown:permission"]])(
    "refuses malformed review permissions (%j) before preparing code",
    (permissions) => {
      const malformed = { ...panel, uiBundle: { ...panel.uiBundle!, permissions } };
      render(<SandboxedCustomPanel panel={malformed as NixPanel} />);
      expect(screen.queryByRole("button", { name: "Open panel once" })).toBeNull();
      expect(agent.client.openModuleUI).not.toHaveBeenCalled();
    },
  );

  it("shows the preparation error to the operator without mounting a frame", async () => {
    agent.client.openModuleUI.mockRejectedValueOnce(new Error("Panel disabled by operator"));
    const view = render(<SandboxedCustomPanel panel={panel} />);
    fireEvent.click(screen.getByRole("button", { name: "Open panel once" }));
    expect((await screen.findByRole("alert")).textContent).toContain("Panel disabled by operator");
    expect(view.container.querySelector("iframe")).toBeNull();
    expect(agent.client.openModuleUI).toHaveBeenCalledTimes(1);
  });

  it.each([
    { actions: { status: {} } },
    { actions: {} },
    { actionIds: [] },
    { permissions: undefined },
    { settings: { unexpected: true } },
  ])("refuses an inconsistent action grant before launching a frame", async (response) => {
    issueDocument("", ["actions:run"], undefined, response);
    const view = render(<SandboxedCustomPanel panel={panel} />);
    fireEvent.click(screen.getByRole("button", { name: "Open panel once" }));
    expect((await screen.findByRole("alert")).textContent).toContain("Refresh the project");
    expect(view.container.querySelector("iframe")).toBeNull();
    expect(agent.client.runModuleAction).not.toHaveBeenCalled();
  });

  it.each(["unexpected dev server", "different dev origin", "expanded rights"])(
    "discards the prepared document on %s and only opens from a newly reviewed snapshot",
    async (change) => {
      const devOrigin = change === "expanded rights" ? undefined : "http://127.0.0.1:5174";
      const permissions: Permission[] =
        change === "expanded rights" ? ["actions:run", "config:patch"] : ["actions:run"];
      const previous = change === "different dev origin" ? "http://127.0.0.1:5173" : undefined;
      issueDocument(devOrigin ? `${devOrigin}/discarded` : "", permissions);
      const view = render(
        <SandboxedCustomPanel
          panel={{ ...panel, uiReview: { revision: reviewRevision, devOrigin: previous } }}
        />,
      );
      fireEvent.click(screen.getByRole("button", { name: "Open panel once" }));
      expect((await screen.findByRole("alert")).textContent).toContain("Refresh the project");
      expect(screen.queryByTitle("Dashboard")).toBeNull();
      expect(screen.queryByRole("button", { name: "Open panel once" })).toBeNull();
      const revision = "2".repeat(64);
      issueDocument(devOrigin ? `${devOrigin}/fresh` : "", permissions);
      const refreshed = {
        ...panel,
        uiReview: { revision, devOrigin },
        uiBundle: { ...panel.uiBundle!, permissions },
      };
      view.rerender(<SandboxedCustomPanel panel={refreshed} />);
      expect(screen.queryByTitle("Dashboard")).toBeNull();
      expect(agent.client.openModuleUI).toHaveBeenCalledTimes(1);
      fireEvent.click(screen.getByRole("button", { name: "Open panel once" }));
      const frame = await screen.findByTitle<HTMLIFrameElement>("Dashboard");
      expect(frame.src).toContain(devOrigin ? `${devOrigin}/fresh` : asset);
      expect(agent.client.openModuleUI.mock.calls.map(([req]) => req.reviewRevision)).toEqual([
        reviewRevision,
        revision,
      ]);
    },
  );

  it.each(["cancel", "project switch", "credential change", "unmount"])(
    "aborts pending preparation on %s",
    async (cause) => {
      const pending = Promise.withResolvers<void>();
      issueDocument("", ["service:proxy"], pending.promise);
      const view = render(<SandboxedCustomPanel panel={panel} />);
      fireEvent.click(screen.getByRole("button", { name: "Open panel once" }));
      const [, options] = agent.client.openModuleUI.mock.calls[0]!;
      if (cause === "cancel")
        fireEvent.click(screen.getByRole("button", { name: "Cancel opening" }));
      else if (cause === "unmount") view.unmount();
      else {
        if (cause === "credential change") agent.identity.token = "replacement";
        else agent.identity.selectedProjectId = "other";
        view.rerender(<SandboxedCustomPanel panel={panel} />);
      }
      expect(options.signal.aborted).toBe(true);
      await act(async () => {
        pending.resolve();
        await pending.promise;
      });
      expect(agent.client.getModuleOutputs).not.toHaveBeenCalled();
      expect(agent.client.openModuleUI).toHaveBeenCalledTimes(1);
      expect(screen.queryByTitle("Dashboard")).toBeNull();
    },
  );

  it("opens a production bundle once with scripts only and no bearer; requires consent again on a project switch", async () => {
    issueDocument();
    const view = render(<SandboxedCustomPanel panel={panel} />);
    expect(await screen.findByText("Production bundle")).toBeTruthy();
    expect(screen.queryByTitle("Dashboard")).toBeNull();
    expect(view.container.textContent).not.toContain("_ticket/");
    fireEvent.click(screen.getByRole("button", { name: "Open panel once" }));
    const frame = await screen.findByTitle<HTMLIFrameElement>("Dashboard");
    expect(frame.src).toContain(asset);
    expect(frame.src).not.toContain(agent.identity.token);
    expect(frame.getAttribute("sandbox")).toBe("allow-scripts");
    expect(frame.getAttribute("referrerpolicy")).toBe("no-referrer");
    expect(frame.hasAttribute("credentialless")).toBe(true);
    agent.identity.selectedProjectId = "project-b";
    view.rerender(<SandboxedCustomPanel panel={panel} />);
    expect(frame.isConnected).toBe(false);
    expect(screen.queryByTitle("Dashboard")).toBeNull();
    expect(await screen.findByRole("button", { name: "Open panel once" })).toBeTruthy();
    expect(screen.queryByTitle("Dashboard")).toBeNull();
    agent.identity.selectedProjectId = null;
    view.rerender(<SandboxedCustomPanel panel={panel} />);
    expect(screen.getByRole("status").textContent).toContain("select a project");
  });

  it("allows one host review at a time, cancels it on request or stop, and never auto-runs an action", async () => {
    issueDocument("", ["actions:run", "service:proxy"]);
    agent.client.runModuleAction.mockImplementation(async function* () {
      yield { event: { case: "exitCode", value: 0 } };
    });
    const capablePanel = {
      ...panel,
      uiBundle: { ...panel.uiBundle!, permissions: ["actions:run", "service:proxy"] },
    };
    render(<SandboxedCustomPanel panel={capablePanel} />);
    fireEvent.click(await screen.findByRole("button", { name: "Open panel once" }));
    const frame = await screen.findByTitle<HTMLIFrameElement>("Dashboard");
    const port = recordingPort();
    frame.dispatchEvent(new Event("load"));
    const fragment = new URLSearchParams(new URL(frame.src).hash.slice(1));
    discovery(
      { type: "stackpanel:ready", nonce: fragment.get("stackpanel-bridge") },
      frame.contentWindow!,
      [port as unknown as MessagePort],
    );
    const handle = port.onmessage!;
    const send = (data: unknown) => handle(new MessageEvent("message", { data }));
    const proxy = {
      method: "proxyFetch",
      service: "cache",
      path: "/info",
      options: { method: "POST", body: "hidden body" },
    };
    const action = { method: "runAction", action: "status", args: {} };
    act(() => {
      void send({ type: "request", id: 1, call: proxy });
    });
    const review = screen.getByRole("region", { name: "Studio request review" });
    expect(review.textContent).toContain("Body: present (not shown)");
    expect(review.textContent).not.toContain("hidden body");
    await act(async () => {
      await send({ type: "request", id: 2, call: action });
    });
    expect(port.postMessage).toHaveBeenCalledWith(
      expect.objectContaining({ type: "error", id: 2 }),
    );
    expect(screen.getAllByRole("button", { name: "Allow once" })).toHaveLength(1);
    expect(agent.client.runModuleAction).not.toHaveBeenCalled();
    await act(async () => {
      await send({ type: "cancel", id: 1 });
    });
    expect(review.isConnected).toBe(false);
    expect(globalThis.fetch).not.toHaveBeenCalled();

    act(() => {
      void send({ type: "request", id: 3, call: action });
    });
    expect(screen.getByRole("region", { name: "Studio request review" }).textContent).toContain(
      'Action: "status"',
    );
    fireEvent.click(screen.getByRole("button", { name: "Deny request" }));
    expect(agent.client.runModuleAction).not.toHaveBeenCalled();
    act(() => {
      void send({ type: "request", id: 4, call: action });
    });
    fireEvent.click(screen.getByRole("button", { name: "Allow once" }));
    await waitFor(() => expect(agent.client.runModuleAction).toHaveBeenCalledTimes(1));
    act(() => {
      void send({ type: "request", id: 5, call: action });
    });
    fireEvent.click(screen.getByRole("button", { name: "Stop panel" }));
    expect(agent.client.runModuleAction).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole("region", { name: "Studio request review" })).toBeNull();
    expect(frame.isConnected).toBe(false);
    expect(port.close).toHaveBeenCalledOnce();
  });
});
