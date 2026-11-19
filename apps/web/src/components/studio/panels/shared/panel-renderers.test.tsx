/// <reference types="vite-plus/test/globals" />
import { fromJson, type MessageInitShape } from "@bufbuild/protobuf";
import { ValueSchema } from "@bufbuild/protobuf/wkt";
import {
  createClient,
  createRouterTransport,
  type Client,
  type ServiceImpl,
} from "@connectrpc/connect";
import { TransportProvider } from "@connectrpc/connect-query";
import {
  ModuleService,
  type RunModuleActionRequest,
  type RunModuleActionResponseSchema,
} from "@stackpanel/proto/agent/v1/module";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { StrictMode } from "react";
import type * as AgentHooks from "@/lib/use-agent";
import type * as AgentProvider from "@/lib/agent-provider";
import { PanelRenderer } from "./panel-renderers";
import type { NixPanel } from "./panel-types";

let client: Client<typeof ModuleService>;
const patch = vi.fn();
vi.mock("@/lib/agent-provider", async (importOriginal) => ({
  ...(await importOriginal<typeof AgentProvider>()),
  useModuleServiceClient: () => client,
  useAgentContext: () => ({
    host: "test",
    port: 1,
    token: "test-token",
    selectedProjectId: "test-project",
    isConnected: true,
    isAuthenticated: true,
  }),
}));
vi.mock("@/lib/use-agent", async (importOriginal) => ({
  ...(await importOriginal<typeof AgentHooks>()),
  usePatchNixData: () => ({ mutate: patch, isPending: false }),
}));

type Event = MessageInitShape<typeof RunModuleActionResponseSchema>;
const base: NixPanel = {
  id: "overview",
  title: "Workers",
  module: "queue",
  order: 1,
  slot: "module",
  enabled: true,
  type: "PANEL_TYPE_TABLE",
  fields: [],
  apps: {},
};
const noArgs = { type: "object", additionalProperties: false };

function renderPanel(
  panel: NixPanel,
  service: Partial<ServiceImpl<typeof ModuleService>>,
  panels: NixPanel[] = [],
) {
  const transport = createRouterTransport((router) => router.service(ModuleService, service));
  client = createClient(ModuleService, transport);
  const cache = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <StrictMode>
      <QueryClientProvider client={cache}>
        <TransportProvider transport={transport}>
          <PanelRenderer panel={panel} panels={panels} />
        </TransportProvider>
      </QueryClientProvider>
    </StrictMode>,
  );
}

it("loads table data on request, then confirms typed arguments from the selected row before running it", async () => {
  const requests: RunModuleActionRequest[] = [];
  const queried: string[] = [];
  renderPanel(
    {
      ...base,
      dataAction: "list",
      actions: ["missing", "incomplete"],
      rowActions: ["resize"],
      columns: [{ key: "queue", label: "Queue" }],
    },
    {
      getModule({ moduleId }) {
        queried.push(moduleId);
        return {
          module: {
            id: moduleId,
            enabled: true,
            actions: {
              incomplete: { label: "Unreviewable", outputMode: "stream" },
              list: { label: "Fetch queues", outputMode: "json", argsSchema: noArgs },
              resize: {
                label: "Resize",
                outputMode: "stream",
                confirm: "Change the worker count?",
                argsSchema: {
                  type: "object",
                  additionalProperties: false,
                  required: ["queue", "workers", "drain"],
                  properties: {
                    queue: { type: "string" },
                    workers: { type: "integer" },
                    drain: { type: "boolean", default: false },
                  },
                },
              },
            },
          },
        };
      },
      async *runModuleAction(req): AsyncGenerator<Event> {
        requests.push(req);
        if (req.actionId === "list")
          yield {
            event: {
              case: "json",
              value: fromJson(ValueSchema, {
                rows: [
                  { queue: "slow", workers: 2 },
                  { queue: "fast", workers: 5, unrelated: "not an argument" },
                ],
              }),
            },
          };
        else yield { event: { case: "stdout", value: "Resized fast queue" } };
        yield { event: { case: "exitCode", value: 0 } };
      },
    },
  );
  const load = await screen.findByRole("button", { name: "Fetch queues" });
  expect(requests).toEqual([]);
  expect((screen.getByRole("button", { name: "missing" }) as HTMLButtonElement).disabled).toBe(
    true,
  );
  const incomplete = screen.getByRole<HTMLButtonElement>("button", { name: "Unreviewable" });
  expect(incomplete.disabled).toBe(true);
  expect(incomplete.title).toMatch(/incomplete action details/i);
  fireEvent.click(load);
  await screen.findByText(/exit code 0/i);
  fireEvent.click(
    within(screen.getByRole("dialog")).getAllByRole("button", { name: /close/i })[0]!,
  );
  const resize = within(await screen.findByRole("row", { name: /fast/ })).getByRole("button", {
    name: "Resize",
  });
  fireEvent.click(resize);
  expect(screen.getByDisplayValue("fast")).toBeTruthy();
  expect(screen.getByDisplayValue("5")).toBeTruthy();
  expect(screen.getByText("Change the worker count?")).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(requests.map((req) => req.actionId)).toEqual(["list"]);
  fireEvent.click(resize);
  fireEvent.change(screen.getByRole("spinbutton", { name: /workers/ }), { target: { value: "8" } });
  fireEvent.click(screen.getByRole("button", { name: "Confirm and run" }));
  expect(await screen.findByText("Resized fast queue")).toBeTruthy();
  expect(requests.map(({ moduleId, actionId, args }) => [moduleId, actionId, args])).toEqual([
    ["queue", "list", {}],
    ["queue", "resize", { queue: "fast", workers: 8, drain: false }],
  ]);
  expect([...new Set(queried)]).toEqual(["queue"]);
});

it("shows returned status metrics instead of treating the JSON event as terminal-only text", async () => {
  renderPanel(
    { ...base, type: "PANEL_TYPE_STATUS", dataAction: "metrics" },
    {
      getModule: () => ({
        module: {
          id: "queue",
          enabled: true,
          actions: { metrics: { label: "Refresh status", outputMode: "json", argsSchema: noArgs } },
        },
      }),
      async *runModuleAction(): AsyncGenerator<Event> {
        yield {
          event: {
            case: "json",
            value: fromJson(ValueSchema, { metrics: [{ label: "Pending", value: 42 }] }),
          },
        };
        yield { event: { case: "exitCode", value: 0 } };
      },
    },
  );
  fireEvent.click(await screen.findByRole("button", { name: "Refresh status" }));
  await screen.findByText(/exit code 0/i);
  fireEvent.click(
    within(screen.getByRole("dialog")).getAllByRole("button", { name: /close/i })[0]!,
  );
  expect((await screen.findByRole("term")).textContent).toBe("Pending");
  expect(screen.getByRole("definition").textContent).toBe("42");
});

it("resolves tab IDs locally, skips cycles and renders an editable app-config child", async () => {
  const tabs = {
    ...base,
    type: "PANEL_TYPE_TABS",
    tabs: ["overview", "nested", "foreign", "config"],
  };
  const nested = { ...tabs, id: "nested", title: "Nested", tabs: [tabs.id] };
  const config = {
    ...base,
    id: "config",
    type: "PANEL_TYPE_APP_CONFIG",
    title: "Consumer settings",
    readme: "## Consumer guide",
    fields: [
      {
        name: "queue",
        label: "Queue name",
        value: null,
        type: "FIELD_TYPE_STRING",
        editable: true,
        editPath: "consumer.queue",
      },
    ],
    apps: {
      web: { enabled: true, config: { queue: "default" } },
      legacy: { enabled: false, config: { queue: "retired" } },
    },
  };
  renderPanel(tabs, {}, [
    tabs,
    nested,
    { ...config, id: "foreign", module: "other", title: "Foreign settings" },
    config,
  ]);
  expect(screen.getByText("No available tabs.")).toBeTruthy();
  expect(screen.queryByRole("tab", { name: "Foreign settings" })).toBeNull();
  const tab = screen.getByRole("tab", { name: "Consumer settings" });
  fireEvent.mouseDown(tab, { button: 0 });
  fireEvent.click(tab);
  expect(await screen.findByRole("heading", { name: "Consumer guide" })).toBeTruthy();
  expect(screen.queryByDisplayValue("retired")).toBeNull();
  const queue = screen.getByDisplayValue("default");
  fireEvent.change(queue, { target: { value: "priority" } });
  fireEvent.blur(queue);
  await waitFor(() =>
    expect(patch).toHaveBeenCalledWith({
      entity: "apps",
      key: "web",
      path: "consumer.queue",
      valueType: "string",
      value: '"priority"',
    }),
  );
});
