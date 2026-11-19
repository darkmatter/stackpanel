import { Code, ConnectError, type ConnectRouter, type Interceptor } from "@connectrpc/connect";
import { useQuery as useConnectQuery } from "@connectrpc/connect-query";
import { AgentService as LegacyAgentService } from "@stackpanel/proto/agent-service";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { ProjectService } from "@stackpanel/proto/agent/v1/project";
import { ShellService } from "@stackpanel/proto/agent/v1/shell";
import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query";
import { act, fireEvent, render, renderHook, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AgentProvider, useAgentContext, useModuleServiceClient } from "./agent-provider";
import { useAgentRpcClient } from "./use-agent";

const HEADER = "X-Stackpanel-Project";
const paired = `header.${btoa(JSON.stringify({ agent_id: "paired", exp: 4_070_908_800 })).replace(/=+$/, "")}.signature`;
const credential = { origin: "http://localhost:9876", token: paired };

beforeEach(() => {
  sessionStorage.clear();
  agent.projectsError = null;
  vi.stubGlobal("fetch", async (url: string) => {
    switch (new URL(url).pathname) {
      case "/health":
        return Response.json({ status: "ok", agent_id: "paired", project_root: "/work/shop" });
      case "/api/auth/validate":
        return Response.json({ success: true, data: { valid: true } });
      default:
        throw new Error(`Unexpected request: ${url}`);
    }
  });
});
afterEach(() => vi.unstubAllGlobals());

// The agent, in memory. `routes` serves its v1 services; `legacy` stands in
// for the AgentService and REST reads, which act on the agent's current
// project and are cached under keys without the project.
const agent = vi.hoisted(() => ({
  routes: (_router: ConnectRouter) => {},
  projectsError: null as ConnectError | null,
  legacy: { current: "shop", hold: Promise.resolve() },
}));

// The provider builds its real transport; only the network is replaced, by a
// router transport that keeps the provider's interceptors.
vi.mock("@connectrpc/connect-web", async () => {
  const { createRouterTransport } = await import("@connectrpc/connect");
  return {
    createConnectTransport: ({ interceptors }: { interceptors?: Interceptor[] }) =>
      createRouterTransport(
        (router) => {
          router.rpc(ProjectService.method.listProjects, () => {
            if (agent.projectsError) throw agent.projectsError;
            return {
              projects: [
                { id: "api-2", path: "/work/api", valid: true },
                { id: "shop", path: "/work/shop", valid: true },
              ],
              defaultProjectId: "api-2",
            };
          });
          agent.routes(router);
        },
        { transport: { interceptors } },
      ),
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
      <AgentProvider credential={credential}>
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
    renders.length = 0;
    agent.legacy = { current: "shop", hold: Promise.resolve() };
  });

  it("sends the selected project on Connect calls and keeps it across a reload", async () => {
    const seen = serveShell();
    const tab = renderStudio();

    expect(await screen.findByText("shell: shop")).toBeTruthy();
    expect(seen).toEqual(["shop"]);

    fireEvent.click(screen.getByRole("button", { name: "Select api" }));
    expect(await screen.findByText("shell: api-2")).toBeTruthy();
    expect(seen).toEqual(["shop", "api-2"]);

    tab.unmount();
    renderStudio();
    expect(await screen.findByText("shell: api-2")).toBeTruthy();
    expect(seen).toEqual(["shop", "api-2", "api-2"]);
  });

  it("never renders the previous project's data after a switch", async () => {
    let release!: () => void;
    const released = new Promise<void>((resolve) => {
      release = resolve;
    });
    serveShell((project) => (project === "api-2" ? released : Promise.resolve()));
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

function renderClients() {
  const cache = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return renderHook(
    () => ({
      select: useAgentContext().selectProject,
      error: useAgentContext().error,
      legacy: useAgentRpcClient(),
      modules: useModuleServiceClient(),
    }),
    {
      wrapper: ({ children }) => (
        <QueryClientProvider client={cache}>
          <AgentProvider credential={credential}>{children}</AgentProvider>
        </QueryClientProvider>
      ),
    },
  );
}

describe("module service transport", () => {
  it("does not select an implicit project after authenticated discovery fails", async () => {
    agent.projectsError = new ConnectError("project registry unavailable", Code.Unimplemented);
    const { result } = renderClients();
    await waitFor(() => expect(result.current.error?.message).toContain("project registry unavailable"));
    expect(result.current.modules).toBeNull();
    expect(result.current.legacy).toBeNull();
  });

  it("scopes legacy and module calls to the selected project, including action streams", async () => {
    const seen: { token: string | null; project: string | null }[] = [];
    function record(headers: Headers) {
      seen.push({ token: headers.get("Authorization"), project: headers.get(HEADER) });
    }
    agent.routes = (router) => {
      router.service(LegacyAgentService, {
        getProject: (_req, ctx) => {
          record(ctx.requestHeader);
          return {};
        },
      });
      router.service(ModuleService, {
        listModules: (_req, ctx) => {
          record(ctx.requestHeader);
          return { modules: [] };
        },
        async *runModuleAction(_req, ctx) {
          record(ctx.requestHeader);
          yield { event: { case: "stdout" as const, value: "action output" } };
        },
      });
    };
    const { result } = renderClients();
    expect(result.current.modules).toBeNull();
    await waitFor(() => expect(result.current.modules).not.toBeNull());
    await result.current.modules!.listModules({});

    act(() => result.current.select("api-2"));
    await waitFor(() => expect(result.current.modules).not.toBeNull());
    await result.current.legacy!.getProject({});
    const events = [];
    const stream = result.current.modules!.runModuleAction({
      moduleId: "example",
      actionId: "status",
    });
    for await (const { event } of stream) {
      events.push(event);
    }
    expect(events).toEqual([{ case: "stdout", value: "action output" }]);
    expect(seen).toEqual([
      { token: `Bearer ${paired}`, project: "shop" },
      { token: `Bearer ${paired}`, project: "api-2" },
      { token: `Bearer ${paired}`, project: "api-2" },
    ]);
  });

  it.each([Code.Unimplemented, Code.PermissionDenied, Code.Unavailable])(
    "returns the agent's error from the requested module procedure (%s)",
    async (code) => {
      agent.routes = (router) =>
        router.rpc(ModuleService.method.installModule, () => {
          throw new ConnectError("cannot install the selected ref", code);
        });
      const { result } = renderClients();
      await waitFor(() => expect(result.current.modules).not.toBeNull());
      await expect(result.current.modules!.installModule({ moduleId: "sample" })).rejects.toMatchObject({
        code,
        rawMessage: "cannot install the selected ref",
      });
    },
  );
});
