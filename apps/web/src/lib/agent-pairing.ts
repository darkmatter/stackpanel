"use client";

import { useCallback, useLayoutEffect, useRef, useState } from "react";

const PENDING_RETURN = "stackpanel.agent.pair.return";
const TOKEN = "stackpanel_agent_token";
const STATE = "stackpanel_pair_state";
const CODE = "stackpanel_pair_code";
const NONCE = /^[a-f0-9]{64}$/;
const LIFETIME = 5 * 60_000;

type PendingReturn = { origin: string; state: string; verifier: string; expires: number };
type PairExchange = PendingReturn & { code: string };

function nonce(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
}

function isAgentPeer(origin: string): boolean {
  try {
    const peer = new URL(origin);
    return (
      (peer.protocol === "http:" || peer.protocol === "https:") &&
      peer.origin === origin &&
      origin !== window.location.origin
    );
  } catch {
    return false;
  }
}

function returnedToStudio(popup: Window): boolean {
  // Cross-origin WindowProxies do not permit reading location.origin.
  try {
    const url = new URL(popup.location.href);
    return (
      url.origin === window.location.origin &&
      (url.pathname === "/studio" || url.pathname.startsWith("/studio/"))
    );
  } catch {
    return false;
  }
}

function validToken(token: unknown): token is string {
  return typeof token === "string" && token.length >= 10 && token.length <= 16_384;
}

// Only a popup created by pair() has this tab-local record. Consume it once,
// including on rejection. A claimed agent/Studio origin in the URL proves nothing.
function takeReturn(origin: string): PairExchange | null {
  const url = new URL(window.location.href);
  const fragment = new URLSearchParams(url.hash.slice(1));
  const codes = fragment.getAll(CODE);
  const states = fragment.getAll(STATE);
  let changed = false;
  for (const params of [url.searchParams, fragment]) {
    for (const key of [TOKEN, STATE, CODE, "token"]) {
      if (!params.has(key)) continue;
      params.delete(key);
      if (params === fragment) url.hash = fragment.toString();
      changed = true;
    }
  }
  if (!changed) return null;
  window.history.replaceState(window.history.state, "", url.href);

  const raw = window.sessionStorage.getItem(PENDING_RETURN);
  window.sessionStorage.removeItem(PENDING_RETURN);
  const [state] = states;
  const [code] = codes;
  if (
    !raw ||
    !isAgentPeer(origin) ||
    states.length !== 1 ||
    !state ||
    !NONCE.test(state) ||
    codes.length !== 1 ||
    !code ||
    !NONCE.test(code)
  )
    return null;
  const pending: Partial<PendingReturn> | null = JSON.parse(raw);
  if (
    pending?.origin !== origin ||
    pending.state !== state ||
    typeof pending.verifier !== "string" ||
    !NONCE.test(pending.verifier) ||
    pending.verifier === state ||
    typeof pending.expires !== "number" ||
    !Number.isFinite(pending.expires) ||
    pending.expires <= Date.now()
  )
    return null;
  return { origin, code, state, verifier: pending.verifier, expires: pending.expires };
}

async function redeemReturn(request: PairExchange, signal: AbortSignal): Promise<string> {
  const { code, state, verifier } = request;
  const response = await fetch(`${request.origin}/pair/redeem`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code, state, verifier }),
    signal,
    credentials: "omit",
    redirect: "error",
    cache: "no-store",
    referrerPolicy: "no-referrer",
  });
  if (!response.ok) throw new Error("Pairing exchange failed");
  const data: unknown = await response.json();
  if (
    !data ||
    typeof data !== "object" ||
    !("token" in data) ||
    !validToken(data.token) ||
    Date.now() >= request.expires
  )
    throw new Error("Invalid or expired pairing exchange");
  return data.token;
}

function submitPair(popup: Window, pending: PendingReturn) {
  // Seed the *popup's* Studio storage while its initial about:blank document
  // still has Studio's origin. The fallback works even after losing opener;
  // a callback in the initiating tab or an unrelated Studio window cannot use it.
  const agent = new URL(pending.origin);
  const canReturn =
    agent.protocol === "http:" &&
    agent.port !== "0" &&
    ["localhost", "127.0.0.1", "[::1]"].includes(agent.hostname);
  if (canReturn) popup.sessionStorage.setItem(PENDING_RETURN, JSON.stringify(pending));
  else popup.sessionStorage.removeItem(PENDING_RETURN);
  const returnUrl = new URL(window.location.pathname, window.location.origin);
  const current = new URL(window.location.href);
  for (const key of ["project", "setup"]) {
    const value = current.searchParams.get(key);
    if (value) returnUrl.searchParams.set(key, value);
  }
  // Manual settings need the same endpoint routing hint as CLI launches.
  if (canReturn) returnUrl.searchParams.set("agent", pending.origin);

  const doc = popup.document;
  const form = doc.createElement("form");
  form.method = "post";
  form.action = `${pending.origin}/pair`;
  for (const [name, value] of [
    ["return_to", canReturn ? returnUrl.href : ""],
    ["state", pending.state],
    ["verifier", canReturn ? pending.verifier : ""],
  ] as const) {
    const input = doc.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value;
    form.append(input);
  }
  doc.body.append(form);
  form.submit();
}

export function useAgentPairing(origin: string, acceptToken: (token: string) => void) {
  const [isPairing, setIsPairing] = useState(false);
  const [pairingError, setPairingError] = useState<string | null>(null);
  const cancel = useRef<(() => void) | null>(null);
  const exchange = useRef<PairExchange | null>(null);
  const accept = useRef(acceptToken);
  useLayoutEffect(() => {
    accept.current = acceptToken;
  }, [acceptToken]);

  useLayoutEffect(() => {
    setIsPairing(false);
    setPairingError(null);
    try {
      const pending = takeReturn(origin) ?? exchange.current;
      exchange.current = pending?.origin === origin ? pending : null;
      if (pending?.origin === origin) {
        const controller = new AbortController();
        const { signal } = controller;
        cancel.current = () => {
          controller.abort();
          cancel.current = null;
        };
        setIsPairing(true);
        // StrictMode can clean up and re-run this effect in the same turn.
        // Scrub immediately but submit the one-use exchange only once.
        queueMicrotask(async () => {
          if (signal.aborted) return;
          exchange.current = null;
          try {
            const token = await redeemReturn(pending, signal);
            if (!signal.aborted) accept.current(token);
          } catch {
            if (!signal.aborted)
              setPairingError("Could not finish pairing. Open the pairing window again.");
          } finally {
            if (!signal.aborted) {
              cancel.current = null;
              setIsPairing(false);
            }
          }
        });
      }
    } catch {
      setPairingError("Could not finish pairing. Open the pairing window again.");
    }
    return () => {
      cancel.current?.();
    };
  }, [origin]);

  const pair = useCallback(() => {
    cancel.current?.();
    setIsPairing(false);
    setPairingError(null);
    if (!isAgentPeer(origin)) {
      setPairingError("Pairing requires a separate agent origin.");
      return;
    }
    const popup = window.open("about:blank", "_blank", "popup,width=560,height=620");
    if (!popup) {
      setPairingError("Your browser blocked the pairing popup. Allow popups, then try again.");
      return;
    }
    const state = nonce();
    const expires = Date.now() + LIFETIME;
    const finish = (error: string | null) => {
      cancel.current?.();
      setIsPairing(false);
      setPairingError(error);
    };
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== origin || event.source !== popup || Date.now() >= expires) return;
      const data: unknown = event.data;
      if (
        !data ||
        typeof data !== "object" ||
        !("type" in data) ||
        data.type !== "stackpanel.agent.pair" ||
        !("state" in data) ||
        data.state !== state ||
        !("token" in data) ||
        !validToken(data.token)
      )
        return;
      finish(null);
      accept.current(data.token);
    };
    window.addEventListener("message", onMessage);
    const timeout = window.setTimeout(
      () => finish("Pairing timed out. Open the pairing window again."),
      LIFETIME,
    );
    const closed = window.setInterval(() => {
      if (popup.closed) finish("Pairing window closed. Try connecting again.");
      else if (returnedToStudio(popup)) finish(null);
    }, 1000);
    cancel.current = () => {
      window.removeEventListener("message", onMessage);
      window.clearTimeout(timeout);
      window.clearInterval(closed);
      cancel.current = null;
      // The no-opener fallback leaves the user working in the returned tab.
      if (!popup.closed && !returnedToStudio(popup)) popup.close();
    };
    try {
      submitPair(popup, { origin, state, verifier: nonce(), expires });
      setIsPairing(true);
    } catch {
      finish("Could not start pairing. Allow browser storage and try again.");
    }
  }, [origin]);

  return { pair, isPairing, pairingError };
}
