import type { ConnectRouter, Interceptor } from "@connectrpc/connect";
import { useQuery as useConnectQuery } from "@connectrpc/connect-query";
import { ShellService } from "@stackpanel/proto/agent/v1/shell";
import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AgentProvider, useAgentContext } from "./agent-provider";

const HEADER = "X-Stackpanel-Project";

// The agent, in memory. `routes` serves its v1 services; `legacy` stands in
// for the AgentService and REST reads, which act on the agent's current
// project and are cached under keys without the project.
const agent = vi.hoisted(() => ({
  routes: (_router: ConnectRouter) => {},
  legacy: { current: "shop", hold: Promise.resolve() },
}));

// The provider builds its real transport; only the network is replaced, by a
// router transport that keeps the provider's interceptors.
vi.mock("@connectrpc/connect-web", async () => {
  const { createRouterTransport } = await import("@connectrpc/connect");
  return {
    createConnectTransport: ({ interceptors }: { interceptors?: Interceptor[] }) =>
      createRouterTransport((router) => agent.routes(router), { transport: { interceptors } }),
  };
});

type Render = { selectedProjectId: string | null; shell: string; apps: string };
const renders: Render[] = [];

function Probe() {
  const { selectedProjectId, selectProject } = useAgentContext();
  const shell = useConnectQuery(ShellService.method.getShellStatus, {});
  const apps = useQuery({
    queryKey: ["agent", "apps"],
    queryFn: async () => {
      await agent.legacy.hold;
      return agent.legacy.current;
    },
  });
  const view = {
    selectedProjectId,
    shell: shell.data?.changedFiles.join(",") ?? "…",
    apps: apps.data ?? "…",
  };
  renders.push(view);
  return (
    <>
      <p>shell: {view.shell}</p>
      <p>apps: {view.apps}</p>
      <button type="button" onClick={() => selectProject("api-2")}>
        Select api
      </button>
    </>
  );
}

function renderStudio() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <AgentProvider token="paired-token">
        <Probe />
      </AgentProvider>
    </QueryClientProvider>,
  );
}

// ShellService answers for the project the header names, or for the agent's
// current project ("shop") without one.
function serveShell(beforeReply: (project: string | null) => Promise<void> = async () => {}) {
  const seen: (string | null)[] = [];
  agent.routes = (router) =>
    router.service(ShellService, {
      getShellStatus: async (_req, ctx) => {
        const project = ctx.requestHeader.get(HEADER);
        seen.push(project);
        await beforeReply(project);
        return { changedFiles: [project ?? "shop"] };
      },
    });
  return seen;
}

describe("AgentProvider project selection", () => {
  beforeEach(() => {
    sessionStorage.clear();
    renders.length = 0;
    agent.legacy = { current: "shop", hold: Promise.resolve() };
  });

  it("sends the selected project on Connect calls and keeps it across a reload", async () => {
    const seen = serveShell();
    const tab = renderStudio();

    expect(await screen.findByText("shell: shop")).toBeTruthy();
    expect(seen).toEqual([null]);

    fireEvent.click(screen.getByRole("button", { name: "Select api" }));
    expect(await screen.findByText("shell: api-2")).toBeTruthy();
    expect(seen).toEqual([null, "api-2"]);

    tab.unmount();
    renderStudio();
    expect(await screen.findByText("shell: api-2")).toBeTruthy();
    expect(seen).toEqual([null, "api-2", "api-2"]);
  });

  it("never renders the previous project's data after a switch", async () => {
    let release!: () => void;
    const released = new Promise<void>((resolve) => {
      release = resolve;
    });
    serveShell((project) => (project ? released : Promise.resolve()));
    renderStudio();
    expect(await screen.findByText("shell: shop")).toBeTruthy();
    expect(await screen.findByText("apps: shop")).toBeTruthy();

    // The picker opens the project over REST first, which moves the agent's
    // current project, and then selects it. Hold the new answers so the
    // in-between state can be observed.
    agent.legacy = { current: "api", hold: released };
    fireEvent.click(screen.getByRole("button", { name: "Select api" }));
    expect(await screen.findByText("shell: …")).toBeTruthy();
    expect(screen.getByText("apps: …")).toBeTruthy();

    release();
    expect(await screen.findByText("shell: api-2")).toBeTruthy();
    expect(await screen.findByText("apps: api")).toBeTruthy();

    const afterSwitch = renders.filter((r) => r.selectedProjectId === "api-2");
    expect(afterSwitch.length).toBeGreaterThan(0);
    expect(afterSwitch.filter((r) => r.shell === "shop" || r.apps === "shop")).toEqual([]);
  });
});
