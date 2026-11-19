import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { agentTokenKey, canonicalAgentOrigin, fetchWithAgentIdentity } from "./agent-identity";
import { AgentProvider, useAgentContext } from "./agent-provider";

const token = `h.${btoa(JSON.stringify({ agent_id: "first", exp: 4_070_908_800 })).replace(/=+$/, "")}.s`;
const original = "http://localhost:9876";

function SessionStatus() {
  const { token, healthStatus } = useAgentContext();
  return (
    <p>
      {healthStatus}:{token ? "authenticated" : "unpaired"}
    </p>
  );
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.mocked(localStorage.getItem).mockReset();
});

describe("endpoint-bound credentials", () => {
  it("canonicalizes the hostname but does not collapse aliases or ports", () => {
    expect(canonicalAgentOrigin("LOCALHOST", 80)).toBe("http://localhost");
    expect(agentTokenKey(canonicalAgentOrigin("127.0.0.1", 9876))).not.toBe(
      agentTokenKey(original),
    );
    expect(() => canonicalAgentOrigin("localhost/ignored", 9876)).toThrow();
  });

  it("uses only the selected endpoint's credential, even if an alias reports the same agent", async () => {
    const stored = new Map([
      [agentTokenKey(original), token],
      ["stackpanel.agent.token", token],
    ]);
    vi.mocked(localStorage.getItem).mockImplementation((key) => stored.get(key) ?? null);
    let identity = "first";
    const request = vi.fn(async (url: string, _init: RequestInit) =>
      Response.json(
        new URL(url).pathname === "/health"
          ? { status: "ok", agent_id: identity }
          : { valid: true },
      ),
    );
    vi.stubGlobal("fetch", request);
    const cache = new QueryClient();
    const view = (host: string, port: number) => (
      <QueryClientProvider client={cache}>
        <AgentProvider host={host} port={port} requestedProjectId="project-1">
          <SessionStatus />
        </AgentProvider>
      </QueryClientProvider>
    );
    const tab = render(view("LOCALHOST", 9876));
    await screen.findByText("available:authenticated");
    tab.rerender(view("127.0.0.1", 9876));
    expect(screen.queryByText("available:authenticated")).toBeNull();
    await screen.findByText("available:unpaired");
    tab.rerender(view("localhost", 9877));
    await screen.findByText("available:unpaired");
    identity = "replacement";
    tab.rerender(view("localhost", 9876));
    await screen.findByText("available:unpaired");

    expect(request.mock.calls.map(([url]) => url)).toEqual([
      `${original}/health`,
      `${original}/api/auth/validate`,
      "http://127.0.0.1:9876/health",
      "http://localhost:9877/health",
      `${original}/health`,
    ]);
    for (const [url, init] of request.mock.calls) {
      const headers = new Headers(init.headers);
      expect(headers.get("Authorization")).toBe(
        url.endsWith("/validate") ? `Bearer ${token}` : null,
      );
      expect(headers.has("X-Stackpanel-Token")).toBe(false);
      expect(init.redirect).toBe("error");
      expect(init.credentials).toBe("omit");
    }
    expect(localStorage.removeItem).toHaveBeenCalledWith(agentTokenKey(original));
  });

  it("does not expose a candidate while the agent is validating it", async () => {
    const { promise: validation, resolve: finish } = Promise.withResolvers<Response>();
    const request = vi.fn(async (url: string) =>
      url.endsWith("/health") ? Response.json({ status: "ok", agent_id: "first" }) : validation,
    );
    vi.stubGlobal("fetch", request);
    render(
      <QueryClientProvider client={new QueryClient()}>
        <AgentProvider credential={{ origin: original, token }} requestedProjectId="project-1">
          <SessionStatus />
        </AgentProvider>
      </QueryClientProvider>,
    );
    await waitFor(() => expect(request).toHaveBeenCalledTimes(2));
    expect(screen.queryByText(/:authenticated/)).toBeNull();
    finish(Response.json({ valid: true }));
    await screen.findByText("available:authenticated");
  });

  it("rechecks identity at send time, rejects a different origin, and refuses redirects", async () => {
    let identity = "first";
    const request = vi.fn(async (url: string) =>
      url.endsWith("/health")
        ? Response.json({ status: "ok", agent_id: identity })
        : Response.json({}),
    );
    vi.stubGlobal("fetch", request);
    const init = { headers: { Authorization: `Bearer ${token}` }, redirect: "follow" as const };
    await expect(
      fetchWithAgentIdentity(original, token, "http://localhost:9877/api", init),
    ).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
    await fetchWithAgentIdentity(original, token, `${original}/api`, init);
    expect(request).toHaveBeenLastCalledWith(
      `${original}/api`,
      expect.objectContaining({ redirect: "error", credentials: "omit" }),
    );
    identity = "replacement";
    await expect(
      fetchWithAgentIdentity(original, token, `${original}/api`, init),
    ).rejects.toThrow();
    expect(request.mock.calls.map(([url]) => url)).toEqual([
      `${original}/health`,
      `${original}/api`,
      `${original}/health`,
    ]);
  });
});
