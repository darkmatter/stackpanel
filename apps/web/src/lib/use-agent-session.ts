import { useCallback, useEffect, useState } from "react";
import {
  agentTokenKey,
  type PublicAgentHealth,
  readPublicAgentHealth,
  tokenAgentId,
} from "./agent-identity";
import { useAgentPairing } from "./agent-pairing";

type Session = {
  healthStatus: "checking" | "available" | "unavailable";
  projectRoot: string | null;
  validatedToken: string | null;
  error: string | null;
};
const initial: Session = {
  healthStatus: "checking",
  projectRoot: null,
  validatedToken: null,
  error: null,
};

// The owner is keyed by canonical origin. Candidate credentials never escape
// this hook: consumers receive only a credential authenticated by that endpoint.
export function useAgentSession(origin: string, providedToken?: string | null) {
  const key = agentTokenKey(origin);
  const [local, setLocal] = useState<string | null>(() =>
    typeof window === "undefined" ? null : (window.localStorage.getItem(key) ?? null),
  );
  const [override, setOverride] = useState<string | null | undefined>();
  const candidate = override !== undefined ? override : (providedToken ?? local);
  const [session, setSession] = useState(initial);
  const accept = useCallback((value: string) => setOverride(value), []);
  const pairing = useAgentPairing(origin, accept);

  useEffect(() => {
    // The old key has no proven destination; it cannot be migrated safely.
    localStorage.removeItem("stackpanel.agent.token");
    const onStorage = (event: StorageEvent) => {
      if (event.storageArea !== localStorage || (event.key !== key && event.key !== null)) return;
      setLocal(localStorage.getItem(key));
      setOverride(undefined);
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, [key]);

  useEffect(() => {
    const controller = new AbortController();
    const { signal } = controller;
    let timer: number | undefined;
    let persistPairing = candidate != null && candidate === override;
    let identityRejected = false;
    const check = async () => {
      let health: PublicAgentHealth | undefined;
      try {
        health = await readPublicAgentHealth(origin, signal);
        if (signal.aborted) return;
        if (candidate) {
          if (identityRejected || !health.agentId || tokenAgentId(candidate) !== health.agentId) {
            identityRejected = true;
            if (localStorage.getItem(key) === candidate) localStorage.removeItem(key);
            throw new Error("Agent identity changed or the pairing expired. Pair again.");
          }
          const response = await fetch(`${origin}/api/auth/validate`, {
            headers: { Authorization: `Bearer ${candidate}` },
            signal,
            redirect: "error",
            credentials: "omit",
            cache: "no-store",
            referrerPolicy: "no-referrer",
          });
          if (!response.ok)
            throw new Error(`Agent authentication failed (${response.status}). Pair again.`);
          const body = await response.json();
          if ((body?.data ?? body)?.valid !== true)
            throw new Error("Invalid agent authentication response");
          if (signal.aborted) return;
          // Don't persist built-in demo / build-time credentials or overwrite a
          // pairing changed in another tab based on a periodic validation.
          if (persistPairing) {
            localStorage.setItem(key, candidate);
            persistPairing = false;
          }
        }
        setSession({
          healthStatus: "available",
          projectRoot: health.projectRoot,
          validatedToken: candidate,
          error: null,
        });
      } catch (error) {
        if (signal.aborted) return;
        setSession({
          healthStatus: health ? "available" : "unavailable",
          projectRoot: health?.projectRoot ?? null,
          validatedToken: null,
          error: health && error instanceof Error ? error.message : null,
        });
      } finally {
        if (!signal.aborted) timer = window.setTimeout(() => void check(), 5000);
      }
    };
    void check();
    return () => {
      controller.abort();
      clearTimeout(timer);
    };
  }, [candidate, key, origin, override]);

  const clearPairing = useCallback(() => {
    localStorage.removeItem(key);
    setLocal(null);
    setOverride(null);
    setSession(initial);
  }, [key]);
  return {
    healthStatus: session.healthStatus,
    projectRoot: session.projectRoot,
    token: candidate === session.validatedToken ? candidate : null,
    isPairing: pairing.isPairing,
    pairingError: pairing.pairingError ?? session.error,
    pair: pairing.pair,
    clearPairing,
  };
}
