"use client";

import { useEffect, useState } from "react";
import { useAgentContext } from "./agent-provider";
import { useAgentSSE } from "./agent-sse-provider";
import { useProjectContext } from "./project-provider";

// Setup links may select only a loopback agent, never an arbitrary remote host.
export function parseSetupEndpoint(value: string): { host: string; port: number } | null {
  try {
    const url = new URL(value);
    if (
      url.protocol !== "http:" ||
      !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) ||
      url.username ||
      url.password ||
      url.pathname !== "/" ||
      url.search ||
      url.hash
    )
      return null;
    const port = Number(url.port || "80");
    return Number.isInteger(port) && port > 0 && port <= 65535
      ? { host: url.hostname, port }
      : null;
  } catch {
    return null;
  }
}

export function SetupReadiness({ session, projectId }: { session: string; projectId: string }) {
  const { host, port, token, isAuthenticated } = useAgentContext();
  const { isAlive, connectionInfo } = useAgentSSE();
  const { currentProject, error: projectError } = useProjectContext();
  const [status, setStatus] = useState("Waiting for pairing and repository connection…");
  const [attempt, setAttempt] = useState(0);
  const root = currentProject?.path;
  const actualId = currentProject?.id;
  const connectionRoot = connectionInfo?.projectRoot;

  useEffect(() => {
    if (
      !isAuthenticated ||
      !token ||
      !isAlive ||
      !root ||
      actualId !== projectId ||
      connectionRoot !== root
    ) {
      setStatus("Waiting for the selected repository and a live authenticated connection…");
      return;
    }
    const controller = new AbortController();
    const base = `http://${host}:${port}`;
    const headers = { "X-Stackpanel-Token": token, "X-Stackpanel-Project": projectId };
    const check = async () => {
      try {
        setStatus("Loading repository configuration…");
        const config = await fetch(
          `${base}/api/nix/config?project=${encodeURIComponent(projectId)}&setup=${encodeURIComponent(session)}`,
          { headers, signal: controller.signal },
        );
        if (!config.ok)
          throw new Error(`Could not load repository configuration (${config.status})`);
        const body = await config.json();
        if (!body.success || !body.data?.config || typeof body.data.config !== "object")
          throw new Error("Agent returned no repository configuration");
        const ready = await fetch(
          `${base}/api/setup/ready?project=${encodeURIComponent(projectId)}`,
          {
            method: "POST",
            headers: { ...headers, "Content-Type": "application/json" },
            body: JSON.stringify({ session }),
            signal: controller.signal,
          },
        );
        if (!ready.ok)
          throw new Error(
            `Setup confirmation failed (${ready.status}). Check the terminal or restart setup if the session expired.`,
          );
        if (!controller.signal.aborted)
          setStatus("Studio ready — repository loaded and connected.");
      } catch (error) {
        if (!controller.signal.aborted)
          setStatus(error instanceof Error ? error.message : "Studio verification failed");
      }
    };
    void check();
    return () => controller.abort();
  }, [
    session,
    projectId,
    host,
    port,
    token,
    isAuthenticated,
    isAlive,
    root,
    actualId,
    connectionRoot,
    attempt,
  ]);

  return (
    <div className="border-b p-3 text-sm" data-testid="setup-readiness">
      <p role="status">{projectError ? projectError.message : status}</p>
      <button type="button" className="mt-1 underline" onClick={() => setAttempt((n) => n + 1)}>
        Retry verification
      </button>
    </div>
  );
}
