/// <reference types="vite-plus/test/globals" />
import { act, cleanup, render, renderHook } from "@testing-library/react";
import type { ComponentProps, PropsWithChildren } from "react";
import { checkAgentIdentity } from "./agent-identity";
import { AgentSSEProvider, useAgentSSE, useAgentSSEEvent } from "./agent-sse-provider";

vi.mock(import("./agent-identity"), async (importOriginal) => ({
  ...(await importOriginal()),
  checkAgentIdentity: vi.fn(),
}));

const identity = vi.mocked(checkAgentIdentity);
const fetchEvents = vi.fn<typeof fetch>();
const diagnostics = "module.dev.diagnostics";
const token = "private-token";

function eventStream() {
  let writer!: ReadableStreamDefaultController<Uint8Array>;
  const cancel = vi.fn();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      writer = controller;
    },
    cancel,
  });
  return {
    cancel,
    writer,
    send(event: string, data: unknown) {
      writer.enqueue(
        new TextEncoder().encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
      );
    },
    response: new Response(body, {
      headers: { "Content-Type": "text/event-stream; charset=utf-8" },
    }),
  };
}

function provider(props: Omit<ComponentProps<typeof AgentSSEProvider>, "children">) {
  return function Wrapper({ children }: PropsWithChildren) {
    return <AgentSSEProvider {...props}>{children}</AgentSSEProvider>;
  };
}

async function advance(ms: number) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  identity.mockReset().mockResolvedValue(undefined);
  fetchEvents.mockReset();
  vi.stubGlobal("fetch", fetchEvents);
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

it("checks identity before its one stream and sends the token only in the bearer header", async () => {
  const verification = Promise.withResolvers<void>();
  identity.mockReturnValueOnce(verification.promise);
  const stream = eventStream();
  fetchEvents.mockResolvedValueOnce(stream.response);
  const named = vi.fn();
  const all = vi.fn();
  const hook = renderHook(
    () => {
      useAgentSSEEvent("file", named);
      useAgentSSEEvent("*", all);
      return useAgentSSE();
    },
    { wrapper: provider({ host: "LOCALHOST", token, projectId: "shop", setupSession: "s 1" }) },
  );

  act(() => hook.result.current.connect());
  expect(identity).toHaveBeenCalledTimes(1);
  expect(fetchEvents).not.toHaveBeenCalled();
  await act(async () => verification.resolve());

  expect(fetchEvents).toHaveBeenCalledTimes(1);
  const [input, init] = fetchEvents.mock.calls[0]!;
  const url = new URL(String(input));
  expect(url.origin + url.pathname).toBe("http://localhost:9876/api/events");
  expect(Object.fromEntries(url.searchParams)).toEqual({ setup: "s 1", project: "shop" });
  expect(url.href).not.toContain(token);
  expect(new Headers(init?.headers).get("Authorization")).toBe(`Bearer ${token}`);
  expect(init?.redirect).toBe("error");
  expect(identity).toHaveBeenCalledWith(url.origin, token, init?.signal);

  // Both the SSE framing and a UTF-8 codepoint straddle network chunks.
  const bytes = new TextEncoder().encode(
    ': keepalive\r\nevent: file\r\ndata: {"path":\r\ndata: "café"}\r\n\r\n',
  );
  const split = bytes.indexOf(0xc3) + 1;
  await act(async () => {
    stream.writer.enqueue(bytes.subarray(0, 17));
    stream.writer.enqueue(bytes.subarray(17, split));
    stream.writer.enqueue(bytes.subarray(split));
  });
  expect(named).toHaveBeenCalledExactlyOnceWith(
    { path: "café" },
    expect.objectContaining({ event: "file" }),
  );
  expect(all.mock.calls).toEqual(named.mock.calls);
  expect(hook.result.current.lastEvent?.rawEvent.data).toBe('{"path":\n"café"}');

  hook.unmount();
  expect(init?.signal?.aborted).toBe(true);
  expect(stream.cancel).toHaveBeenCalledTimes(1);
  await advance(60_000);
  expect(identity).toHaveBeenCalledTimes(1);
});

it("does not consult storage or connect without an explicit token", () => {
  const storage = vi.spyOn(localStorage, "getItem").mockReturnValue("legacy-token");
  const hook = renderHook(useAgentSSE, { wrapper: provider({}) });
  expect(hook.result.current.status).toBe("idle");
  act(() => hook.result.current.connect());
  expect(storage).not.toHaveBeenCalled();
  expect(identity).not.toHaveBeenCalled();
  expect(fetchEvents).not.toHaveBeenCalled();
});

it("aborts a manually opened identity check on unmount, even if it resolves late", async () => {
  const verification = Promise.withResolvers<void>();
  identity.mockReturnValueOnce(verification.promise);
  const hook = renderHook(useAgentSSE, { wrapper: provider({ token, autoConnect: false }) });
  expect(identity).not.toHaveBeenCalled();
  act(() => hook.result.current.connect());
  const signal = identity.mock.calls[0]![2];
  hook.unmount();
  expect(signal?.aborted).toBe(true);
  await act(async () => verification.resolve());
  await advance(60_000);
  expect(fetchEvents).not.toHaveBeenCalled();
  expect(identity).toHaveBeenCalledTimes(1);
});

it("rechecks identity after EOF and never sends the bearer to a replacement agent", async () => {
  const first = eventStream();
  const restored = eventStream();
  fetchEvents.mockResolvedValueOnce(first.response).mockResolvedValueOnce(restored.response);
  identity.mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("wrong agent"));
  const listener = vi.fn();
  const hook = renderHook(
    () => {
      useAgentSSEEvent("changed", listener);
      return useAgentSSE();
    },
    { wrapper: provider({ token, projectId: "shop" }) },
  );
  await act(async () => {
    first.send(diagnostics, { projectId: "shop" });
    first.writer.close();
  });
  expect(hook.result.current.status).toBe("error");
  const replay = vi.fn();
  const unsubscribe = hook.result.current.addEventListener(diagnostics, replay);
  expect(replay).toHaveBeenCalledTimes(1);
  unsubscribe();
  await advance(3_000);
  expect(identity).toHaveBeenCalledTimes(2);
  expect(hook.result.current.error?.message).toBe("wrong agent");
  expect(fetchEvents).toHaveBeenCalledTimes(1);
  const afterMismatch = vi.fn();
  hook.result.current.addEventListener(diagnostics, afterMismatch)();
  expect(afterMismatch).not.toHaveBeenCalled();
  await advance(3_000);
  expect(identity).toHaveBeenCalledTimes(3);
  expect(fetchEvents).toHaveBeenCalledTimes(2);
  await act(async () => restored.send("changed", "restored"));
  expect(listener).toHaveBeenCalledExactlyOnceWith("restored", expect.anything());
});

it("uses pings to extend liveness, aborts a stale stream, and cancels its retry on disconnect", async () => {
  const stream = eventStream();
  fetchEvents.mockResolvedValueOnce(stream.response);
  const { result } = renderHook(useAgentSSE, { wrapper: provider({ token }) });
  await act(async () =>
    stream.send("connected", { agentId: "a", hasProject: true, projectRoot: "/shop" }),
  );
  expect(result.current.connectionInfo).toEqual({
    agentId: "a",
    hasProject: true,
    projectRoot: "/shop",
  });
  await advance(10_000);
  await act(async () => stream.send("ping", { ts: 123 }));
  expect(result.current.lastHeartbeat).not.toBeNull();
  await advance(10_000);
  expect(result.current.isAlive).toBe(true);
  await advance(2_000);
  expect(result.current.status).toBe("error");
  expect(result.current.isAlive).toBe(false);
  expect(stream.cancel).toHaveBeenCalledTimes(1);
  act(() => result.current.disconnect());
  await advance(60_000);
  expect(result.current.status).toBe("idle");
  expect(identity).toHaveBeenCalledTimes(1);
});

it("replays only the latest diagnostics in the same project and never carries them across a switch", async () => {
  const shop = eventStream();
  const api = eventStream();
  fetchEvents.mockResolvedValueOnce(shop.response).mockResolvedValueOnce(api.response);
  const seen = vi.fn();
  function Diagnostics() {
    const { data } = useAgentSSEEvent<{ revision: string }>(diagnostics, seen);
    return <output>{data?.revision ?? "waiting"}</output>;
  }
  function view(projectId: string, listen: boolean) {
    return (
      <AgentSSEProvider token={token} projectId={projectId}>
        {listen && <Diagnostics />}
      </AgentSSEProvider>
    );
  }
  const tab = render(view("shop", false));
  await act(async () => {
    shop.send(diagnostics, { projectId: "shop", revision: "first" });
    shop.send(diagnostics, { projectId: "shop", revision: "latest" });
  });
  tab.rerender(view("shop", true));
  expect(tab.getByText("latest")).toBeTruthy();
  expect(seen).toHaveBeenCalledTimes(1);
  tab.rerender(view("api", true));
  expect(tab.getByText("waiting")).toBeTruthy();
  expect(shop.cancel).toHaveBeenCalledTimes(1);
  await act(async () => api.send(diagnostics, { projectId: "shop", revision: "wrong" }));
  expect(seen).toHaveBeenCalledTimes(1);
  await act(async () => api.send(diagnostics, { projectId: "api", revision: "new" }));
  expect(tab.getByText("new")).toBeTruthy();
  expect(seen).toHaveBeenCalledTimes(2);
});
