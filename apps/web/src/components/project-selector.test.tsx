import { Code, ConnectError, createRouterTransport } from "@connectrpc/connect";
import { TransportProvider } from "@connectrpc/connect-query";
import { ProjectService } from "@stackpanel/proto/agent/v1/project";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ProjectSelector } from "./project-selector";

const { agentClient, endpoint } = vi.hoisted(() => ({
  agentClient: { getCurrentProject: vi.fn(), openProject: vi.fn() },
  endpoint: { isDemo: false, useLocal: () => {} },
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => () => {} }));
vi.mock("@/lib/agent-endpoint", () => ({ useAgentEndpoint: () => endpoint }));
vi.mock("@/lib/agent-provider", () => ({
  useAgentContext: () => ({
    host: "localhost",
    port: 9876,
    token: "paired-token",
    healthStatus: "available",
    isAuthenticated: true,
  }),
  useAgentClient: () => agentClient,
}));

const shop = { id: "shop-1", name: "shop", path: "/work/shop", valid: true };
const api = { id: "api-2", name: "api", path: "/work/api", valid: true };
const gone = {
  id: "gone-3",
  name: "gone",
  path: "/work/gone",
  valid: false,
  invalidReason: "project directory does not exist",
};

// Serves ProjectService in memory, the way the agent's v1 handler answers.
function renderSelector() {
  const calls = { listProjects: 0 };
  const transport = createRouterTransport(({ service }) => {
    service(ProjectService, {
      listProjects: () => {
        calls.listProjects++;
        return { projects: [shop, api, gone], defaultProjectId: shop.id };
      },
      addProject: () => {
        throw new ConnectError(
          "directory is not a git repository (no .git folder)",
          Code.InvalidArgument,
        );
      },
    });
  });
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <TransportProvider transport={transport}>
        <ProjectSelector />
      </TransportProvider>
    </QueryClientProvider>,
  );
  return calls;
}

async function openPicker() {
  const trigger = await screen.findByRole("combobox");
  await waitFor(() => expect(trigger.hasAttribute("data-disabled")).toBe(false));
  fireEvent.click(trigger);
  await screen.findAllByRole("option");
}

describe("ProjectSelector", () => {
  beforeEach(() => {
    endpoint.isDemo = false;
    agentClient.getCurrentProject.mockResolvedValue({
      has_project: true,
      project: { id: shop.id, name: shop.name, path: shop.path },
    });
    agentClient.openProject.mockImplementation(async (path: string) => ({
      success: true,
      project: { id: "opened", name: "opened", path },
    }));
  });

  it("lists the registry and disables projects the agent reports invalid", async () => {
    renderSelector();
    await openPicker();

    expect(screen.getByRole("option", { name: /gone/ }).getAttribute("aria-disabled")).toBe("true");
    expect(screen.getByText("project directory does not exist")).toBeTruthy();
    expect(screen.getByRole("option", { name: /api/ }).getAttribute("aria-disabled")).toBeNull();
  });

  it("switches projects over REST and refreshes the registry", async () => {
    const calls = renderSelector();
    await openPicker();

    fireEvent.click(screen.getByRole("option", { name: /api/ }));

    await waitFor(() => expect(agentClient.openProject).toHaveBeenCalledWith(api.path));
    await waitFor(() => expect(calls.listProjects).toBe(2));
  });

  it("shows why AddProject rejected the path", async () => {
    renderSelector();
    await openPicker();

    fireEvent.click(screen.getByRole("option", { name: /Add project/ }));
    fireEvent.change(await screen.findByLabelText("Project Path"), {
      target: { value: "/work/plain-dir" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add Project" }));

    expect(
      await screen.findByText("directory is not a git repository (no .git folder)"),
    ).toBeTruthy();
    expect(agentClient.openProject).not.toHaveBeenCalled();
  });

  it("stays off the network in demo mode", async () => {
    endpoint.isDemo = true;
    const calls = renderSelector();

    expect(await screen.findByText("stackpanel-demo")).toBeTruthy();
    expect(calls.listProjects).toBe(0);
    expect(agentClient.getCurrentProject).not.toHaveBeenCalled();
  });
});
