import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vite-plus/test";
import { useAgentPairing } from "./agent-pairing";

const agent = "http://localhost:9876";
const alias = "http://127.0.0.1:9876";
const token = "approved-agent-token";
const type = "stackpanel.agent.pair";
const record = "stackpanel.agent.pair.return";
const state = "ab".repeat(32);
const verifier = "cd".repeat(32);
const code = "fe".repeat(32);

beforeEach(() => {
  window.history.replaceState(null, "", "/studio");
  sessionStorage.clear();
});
afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
  document.querySelectorAll('form[action$="/pair"]').forEach((form) => form.remove());
});

function popupWindow() {
  const seed = vi.fn();
  const popup = {
    document,
    closed: false,
    close: vi.fn(),
    sessionStorage: { setItem: seed, removeItem: vi.fn() },
  };
  const win = popup as unknown as Window;
  return { win, popup, seed };
}

function message(source: Window | null, origin: string, data: unknown) {
  act(() => {
    window.dispatchEvent(new MessageEvent("message", { source, origin, data }));
  });
}

function start(endpoint = agent) {
  const { win, popup, seed } = popupWindow();
  vi.spyOn(window, "open").mockReturnValue(win);
  vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
  const accept = vi.fn();
  const hook = renderHook(({ origin }) => useAgentPairing(origin, accept), {
    initialProps: { origin: endpoint },
  });
  act(() => hook.result.current.pair());
  const form = document.querySelector<HTMLFormElement>('form[action$="/pair"]')!;
  const nonce = form.querySelector<HTMLInputElement>('input[name="state"]')!.value;
  return { ...hook, accept, win, popup, seed, form, nonce };
}

it("submits to the exact endpoint and accepts only the current popup, origin and state", () => {
  window.history.replaceState(
    null,
    "",
    "/studio/m/demo?project=p&setup=s&token=private#stackpanel_agent_token=private",
  );
  const { result, accept, win, seed, form, nonce } = start();
  expect(result.current.isPairing).toBe(true);
  expect(form.method).toBe("post");
  expect(form.action).toBe(`${agent}/pair`);
  expect(form.querySelector<HTMLInputElement>('input[name="return_to"]')?.value).toBe(
    `${window.location.origin}/studio/m/demo?project=p&setup=s&agent=${encodeURIComponent(agent)}`,
  );
  expect(nonce).toMatch(/^[a-f0-9]{64}$/);
  const privateProof = form.querySelector<HTMLInputElement>('input[name="verifier"]')!.value;
  expect(privateProof).toMatch(/^[a-f0-9]{64}$/);
  expect(privateProof).not.toBe(nonce);
  expect(JSON.parse(seed.mock.calls[0]![1])).toMatchObject({
    state: nonce,
    origin: agent,
    verifier: privateProof,
  });
  expect(sessionStorage.getItem(record)).toBeNull(); // no redirect capability in the opener

  const approved = { type, token, state: nonce, origin: agent };
  for (const origin of [
    alias,
    "http://localhost:9877",
    "https://localhost:9876",
    window.location.origin,
    "null",
  ]) {
    message(win, origin, approved);
  }
  message(null, agent, approved);
  message(window, agent, approved);
  message(win, agent, { type, token });
  message(win, agent, { ...approved, state: `wrong-${nonce}` });
  message(win, agent, { ...approved, type: "other" });
  message(win, agent, { ...approved, token: 7 });
  expect(accept).not.toHaveBeenCalled();
  message(win, agent, approved);
  message(win, agent, approved);
  expect(accept.mock.calls).toEqual([[token]]);
  expect(result.current.isPairing).toBe(false);
});

it("includes a manually selected loopback endpoint in the return even without an agent query", () => {
  const endpoint = "http://127.0.0.1:23555";
  const { form } = start(endpoint);
  const address = new URL(form.querySelector<HTMLInputElement>('input[name="return_to"]')!.value);
  expect(address.searchParams.get("agent")).toBe(endpoint);
});

it("does not set redirect state or a return URL for a remote endpoint", () => {
  const { form, seed } = start("https://agent.example");
  expect(form.querySelector<HTMLInputElement>('input[name="return_to"]')!.value).toBe("");
  expect(seed).not.toHaveBeenCalled();
});

it("cancels old attempts on retry, endpoint switch and unmount", () => {
  const { result, rerender, unmount, accept, win, nonce } = start();
  const second = popupWindow();
  vi.mocked(window.open).mockReturnValue(second.win);
  act(() => result.current.pair());
  const nextState = JSON.parse(second.seed.mock.calls[0]![1]).state;
  expect(nextState).not.toBe(nonce);
  message(win, agent, { type, token, state: nonce });
  message(second.win, agent, { type, token, state: nonce });
  rerender({ origin: alias });
  message(second.win, agent, { type, token, state: nextState });
  expect(result.current.isPairing).toBe(false);
  act(() => result.current.pair());
  const lastState = JSON.parse(second.seed.mock.calls[1]![1]).state;
  unmount();
  message(second.win, alias, { type, token, state: lastState });
  expect(accept).not.toHaveBeenCalled();
});

it("refuses a same-origin agent and reports a blocked popup", () => {
  const open = vi.spyOn(window, "open").mockReturnValue(null);
  const hook = renderHook(({ origin }) => useAgentPairing(origin, vi.fn()), {
    initialProps: { origin: window.location.origin },
  });
  act(() => hook.result.current.pair());
  expect(open).not.toHaveBeenCalled();
  hook.rerender({ origin: agent });
  act(() => hook.result.current.pair());
  expect(hook.result.current.pairingError).toContain("blocked");
  expect(hook.result.current.isPairing).toBe(false);
});

it.each(["closed", "expired"])("ignores late messages when the attempt is %s", (reason) => {
  vi.useFakeTimers();
  const { popup, win, nonce, accept, result } = start();
  popup.closed = reason === "closed";
  act(() => vi.advanceTimersByTime(popup.closed ? 1000 : 300_000));
  message(win, agent, { state: nonce, type, token });
  expect(result.current.isPairing).toBe(false);
  expect(result.current.pairingError).not.toBeNull();
  expect(accept).not.toHaveBeenCalled();
});

function returnURL() {
  return `/studio?project=p#stackpanel_pair_state=${state}&stackpanel_pair_code=${code}`;
}

it.each([
  ["query token", `/studio?project=p&token=${token}`, agent, state, 60_000],
  [
    "fragment token",
    `/studio?project=p#stackpanel_pair_state=${state}&stackpanel_agent_token=${token}`,
    agent,
    state,
    60_000,
  ],
  [
    "query state",
    `/studio?project=p&stackpanel_pair_state=${state}#stackpanel_pair_code=${code}`,
    agent,
    state,
    60_000,
  ],
  ["claimed sender", `${returnURL()}&origin=${agent}`, "", state, 60_000],
  ["wrong endpoint", returnURL(), alias, state, 60_000],
  ["wrong state", returnURL(), agent, "cd".repeat(32), 60_000],
  ["expired", returnURL(), agent, state, -1],
  ["ambiguous fragment", `${returnURL()}&stackpanel_pair_code=duplicate`, agent, state, 60_000],
] as const)(
  "discards %s and scrubs URL credential fields",
  async (_name, url, origin, pendingState, lifetime) => {
    const fetch = vi.spyOn(globalThis, "fetch");
    if (origin)
      sessionStorage.setItem(
        record,
        JSON.stringify({ origin, state: pendingState, verifier, expires: Date.now() + lifetime }),
      );
    window.history.replaceState(null, "", url);
    const accept = vi.fn();
    renderHook(() => useAgentPairing(agent, accept));
    await act(async () => {});
    expect(fetch).not.toHaveBeenCalled();
    expect(accept).not.toHaveBeenCalled();
    expect(sessionStorage.getItem(record)).toBeNull();
    expect(window.location.href).not.toContain(token);
    expect(window.location.href).not.toContain(code);
    expect(new URLSearchParams(window.location.search).get("project")).toBe("p");
  },
);

it("redeems a bound code once, only at its endpoint, without putting secrets in the URL", async () => {
  const fetch = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ token }));
  const accept = vi.fn();
  sessionStorage.setItem(
    record,
    JSON.stringify({ origin: agent, state, verifier, expires: Date.now() + 60_000 }),
  );
  window.history.replaceState({ studio: 2 }, "", returnURL());
  const hook = renderHook(() => useAgentPairing(agent, accept), { reactStrictMode: true });
  expect(window.location.hash).toBe("");
  expect(window.history.state).toEqual({ studio: 2 });
  await waitFor(() => expect(accept).toHaveBeenCalledWith(token));
  expect(fetch).toHaveBeenCalledWith(
    `${agent}/pair/redeem`,
    expect.objectContaining({
      method: "POST",
      body: JSON.stringify({ code, state, verifier }),
      redirect: "error",
      referrerPolicy: "no-referrer",
      credentials: "omit",
      cache: "no-store",
    }),
  );
  hook.unmount();
  window.history.replaceState(null, "", returnURL());
  renderHook(() => useAgentPairing(agent, accept));
  await act(async () => {});
  expect(fetch).toHaveBeenCalledTimes(1);
  expect(accept.mock.calls).toEqual([[token]]);
});

it("does not accept an exchange response that arrives after an endpoint switch", async () => {
  const response = Promise.withResolvers<Response>();
  const fetch = vi.spyOn(globalThis, "fetch").mockReturnValue(response.promise);
  sessionStorage.setItem(
    record,
    JSON.stringify({ origin: agent, state, verifier, expires: Date.now() + 60_000 }),
  );
  window.history.replaceState(null, "", returnURL());
  const accept = vi.fn();
  const hook = renderHook(({ origin }) => useAgentPairing(origin, accept), {
    initialProps: { origin: agent },
  });
  await waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
  hook.rerender({ origin: alias });
  await act(async () => {
    response.resolve(Response.json({ token }));
  });
  expect(accept).not.toHaveBeenCalled();
});
