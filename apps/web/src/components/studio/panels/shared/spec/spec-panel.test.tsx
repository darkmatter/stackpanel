/// <reference types="vite-plus/test/globals" />
import { StateProvider } from "@json-render/react";
import { createClient, createRouterTransport, type Client } from "@connectrpc/connect";
import { TransportProvider } from "@connectrpc/connect-query";
import { ModuleService, type RunModuleActionRequest } from "@stackpanel/proto/agent/v1/module";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, within } from "@testing-library/react";
import type * as AgentProvider from "@/lib/agent-provider";
import { ActionButtons, PanelActionScope } from "../panel-action-bar";
import { SpecPanel } from "./spec-panel";

let client: Client<typeof ModuleService>;
vi.mock("@/lib/agent-provider", async (original) => ({
  ...(await original<typeof AgentProvider>()),
  useModuleServiceClient: () => client,
  useAgentContext: () => ({
    host: "host",
    port: 1,
    token: "test",
    selectedProjectId: "project",
    isConnected: true,
    isAuthenticated: true,
  }),
}));

// Observe the handoff at the grant boundary; live-status.test covers actual grants.
vi.mock("./live-status", () => ({
  LiveStatus: ({ app, allowedApps }: { app?: string; allowedApps: readonly string[] }) => (
    <output>{JSON.stringify([app ?? null, allowedApps])}</output>
  ),
}));

const display = {
  root: "root",
  elements: {
    root: {
      type: "Section",
      props: { title: { $state: "/panel/title" } },
      children: ["owner", "app", "load", "workers"],
    },
    owner: { type: "Text", props: { content: { $state: "/module/id" } } },
    app: { type: "Badge", props: { text: { $state: "/app/id" } } },
    load: { type: "Metric", props: { label: "Count", value: { $state: "/data/count" } } },
    workers: {
      type: "Table",
      props: {
        columns: [
          { key: "id", label: "Worker" },
          { key: "ready", label: "Ready" },
        ],
        rows: { $state: "/data/workers" },
      },
    },
  },
  state: { data: { count: 414523, workers: [{ id: "<b>old</b>", ready: false }] } },
};

it("renders only scoped host and spec values, replacing the dataset even when the tree is unchanged", () => {
  // No query/transport providers: this display must not mount a module lookup.
  const view = render(
    <SpecPanel
      panelId="summary"
      title="Queues"
      moduleId="queue"
      appId="web-app"
      document={display}
    />,
    {
      wrapper: ({ children }) => (
        <StateProvider initialState={{ module: { id: "ambient" }, app: { id: "foreign" } }}>
          {children}
        </StateProvider>
      ),
    },
  );
  expect(screen.getByRole("heading", { name: "Queues" })).toBeTruthy();
  expect(screen.getByText("queue")).toBeTruthy();
  expect(screen.getByText("web-app")).toBeTruthy();
  expect(view.container.querySelector("sp-metric")?.shadowRoot?.textContent).toContain("414523");
  const table = within(
    view.container.querySelector("sp-data-table")!.shadowRoot!.querySelector("table")!,
  );
  expect(table.getByRole("columnheader", { name: "Ready" })).toBeTruthy();
  expect(table.getByRole("cell", { name: "<b>old</b>" })).toBeTruthy();
  expect(table.getByRole("cell", { name: "false" })).toBeTruthy();

  const next = { ...display, state: { data: { count: 189456, workers: [{ id: "worker-4" }] } } };
  view.rerender(
    <SpecPanel panelId="summary" title="Queues" moduleId="queue" appId="web-app" document={next} />,
  );
  expect(view.container.querySelector("sp-metric")?.shadowRoot?.textContent).toContain("189456");
  const refreshed = within(
    view.container.querySelector("sp-data-table")!.shadowRoot!.querySelector("table")!,
  );
  expect(refreshed.getByRole("cell", { name: "worker-4" })).toBeTruthy();
  expect(refreshed.queryByRole("cell", { name: "<b>old</b>" })).toBeNull();

  view.rerender(
    <SpecPanel panelId="summary" title="Tasks" moduleId="task-module" document={next} />,
  );
  expect(screen.getByRole("heading", { name: "Tasks" })).toBeTruthy();
  expect(screen.getByText("task-module")).toBeTruthy();
  for (const stale of ["web-app", "Queues", "queue", "ambient", "foreign"])
    expect(screen.queryByText(stale)).toBeNull();
});

it("updates a sibling display from the shared app picker without a module client and resets local selection on owner change", () => {
  const doc = {
    root: "stack",
    elements: {
      stack: { type: "Stack", props: {}, children: ["picker", "selection"] },
      picker: {
        type: "AppPicker",
        props: {
          label: "Target app",
          apps: { $state: "/data/apps" },
          value: { $bindState: "/local/selected" },
        },
      },
      selection: { type: "Text", props: { content: { $state: "/local/selected" } } },
    },
    state: { data: { apps: ["web", "worker"] }, local: { selected: "web" } },
  };
  const view = render(<SpecPanel panelId="deploy" title="Deploy" moduleId="fly" document={doc} />);
  expect(screen.getByText("web")).toBeTruthy();
  const select = view.container
    .querySelector("sp-app-picker")!
    .shadowRoot!.querySelector("select")!;
  fireEvent.change(select, { target: { value: "worker" } });
  expect(screen.getByText("worker")).toBeTruthy();
  expect(screen.queryByText("web")).toBeNull();
  view.rerender(<SpecPanel panelId="deploy" title="Deploy" moduleId="fly" document={{ ...doc }} />);
  expect(screen.getByText("worker")).toBeTruthy();
  fireEvent.change(select, { target: { value: "" } });
  expect(screen.queryByText("worker")).toBeNull();
  view.rerender(<SpecPanel panelId="other" title="Deploy" moduleId="fly" document={doc} />);
  expect(screen.getByText("web")).toBeTruthy();
  expect(screen.queryByText("worker")).toBeNull();
});

it("hands each live read only its own picker choices even for the same action and initial app", () => {
  const elements = {
    red: { type: "StatusView", props: { action: "status", app: { $state: "/local/red" } } },
    blue: { type: "StatusView", props: { action: "status", app: { $state: "/local/blue" } } },
    fixed: { type: "StatusView", props: { action: "status", app: "shared" } },
    global: { type: "StatusView", props: { action: "status" } },
    first: {
      type: "AppPicker",
      props: { apps: { $state: "/data/redApps" }, value: { $bindState: "/local/red" } },
    },
    second: {
      type: "AppPicker",
      props: { apps: ["shared", "b"], value: { $bindState: "/local/blue" } },
    },
  };
  const doc = {
    root: "stack",
    elements: { ...elements, stack: { type: "Stack", props: {}, children: Object.keys(elements) } },
    state: { data: { redApps: ["shared", "r"] }, local: { red: "shared", blue: "shared" } },
  };
  const view = render(<SpecPanel panelId="status" title="Status" moduleId="fly" document={doc} />);
  expect(screen.getByText('["shared",["shared","r"]]')).toBeTruthy();
  expect(screen.getByText('["shared",["shared","b"]]')).toBeTruthy();
  expect(screen.getByText('["shared",["shared"]]')).toBeTruthy();
  expect(screen.getByText("[null,[]]")).toBeTruthy();
  fireEvent.change(
    view.container.querySelector("sp-app-picker")!.shadowRoot!.querySelector("select")!,
    { target: { value: "r" } },
  );
  expect(screen.getByText('["r",["shared","r"]]')).toBeTruthy();
  expect(screen.getByText('["shared",["shared","b"]]')).toBeTruthy();
});

it("rejects the entire invalid panel before mounting controls and leaves neighboring content intact", () => {
  const invalid = {
    ...display,
    elements: {
      ...display.elements,
      root: { ...display.elements.root, children: ["actions", ...display.elements.root.children] },
      actions: { type: "Actions", props: {} },
      workers: { ...display.elements.workers, watch: {} },
    },
  };
  render(
    <>
      <SpecPanel panelId="bad" title="Broken" moduleId="build" appId="web" document={invalid} />
      <SpecPanel panelId="summary" title="Healthy" moduleId="queue" document={display} />
    </>,
  );
  const alert = screen.getByRole("alert");
  for (const hint of ["Broken", "build", "web", "workers", "watch"])
    expect(alert.textContent).toContain(hint);
  expect(screen.queryByRole("button")).toBeNull();
  expect(screen.getByRole("heading", { name: "Healthy" })).toBeTruthy();
});

it("uses only the current owner's declared actions and drops pending confirmations when their scope changes", async () => {
  const requests: RunModuleActionRequest[] = [];
  const transport = createRouterTransport((router) =>
    router.service(ModuleService, {
      getModule: ({ moduleId }) => ({
        module: {
          id: moduleId,
          enabled: true,
          actions: {
            deploy: {
              label: `Deploy ${moduleId}`,
              outputMode: "stream",
              confirm: `Confirm for ${moduleId}?`,
              argsSchema: {
                type: "object",
                properties: { workers: { type: "integer", default: 1 } },
              },
            },
          },
        },
      }),
      async *runModuleAction(req) {
        requests.push(req);
        yield { event: { case: "exitCode" as const, value: 0 } };
      },
    }),
  );
  client = createClient(ModuleService, transport);
  const cache = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const doc = {
    root: "a",
    elements: { a: { type: "Actions", props: { ids: ["deploy", "missing"] } } },
  };
  const panel = (moduleId: string, appId: string, document: unknown) => (
    <SpecPanel panelId="tools" title="Actions" {...{ moduleId, appId, document }} />
  );
  const view = render(panel("queue", "web", doc), {
    wrapper: ({ children }) => (
      <QueryClientProvider client={cache}>
        <TransportProvider transport={transport}>
          <PanelActionScope moduleId="outer">
            <ActionButtons actionIds={["deploy"]} />
            {children}
          </PanelActionScope>
        </TransportProvider>
      </QueryClientProvider>
    ),
  });
  fireEvent.click(await screen.findByRole("button", { name: "Deploy queue" }));
  expect(screen.getByText("Confirm for queue?")).toBeTruthy();
  view.rerender(panel("queue", "mobile", doc));
  expect(screen.queryByRole("dialog")).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Deploy queue" }));
  const changed = { ...doc, state: { data: { revision: 2 } } };
  view.rerender(panel("queue", "mobile", changed));
  expect(screen.queryByRole("dialog")).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Deploy queue" }));
  view.rerender(panel("other", "mobile", changed));
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(screen.queryByRole("button", { name: "Deploy queue" })).toBeNull();
  expect(requests).toHaveLength(0);
  expect((screen.getByRole("button", { name: "missing" }) as HTMLButtonElement).disabled).toBe(
    true,
  );
  expect(screen.getByRole("button", { name: "Deploy outer" })).toBeTruthy();
  fireEvent.click(await screen.findByRole("button", { name: "Deploy other" }));
  expect(screen.getByText("Confirm for other?")).toBeTruthy();
  fireEvent.change(screen.getByRole("spinbutton", { name: /workers/ }), { target: { value: "3" } });
  fireEvent.click(screen.getByRole("button", { name: "Confirm and run" }));
  await screen.findByText(/exit code 0/i);
  expect(requests.map(({ moduleId, actionId, args }) => [moduleId, actionId, args])).toEqual([
    ["other", "deploy", { workers: 3 }],
  ]);
});
