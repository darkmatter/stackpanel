// @vitest-environment jsdom
import {
  Code,
  ConnectError,
  createClient,
  createRouterTransport,
  type Client,
} from "@connectrpc/connect";
import { TransportProvider } from "@connectrpc/connect-query";
import { ModuleService, type OpenModuleUIRequest } from "@stackpanel/proto/agent/v1/module";
import { fireEvent, render, waitFor } from "@testing-library/react";
import { StrictMode } from "react";
import { beforeEach, expect, it, vi } from "vite-plus/test";
import type * as AgentProvider from "@/lib/agent-provider";
import { StudioPanelsProvider } from "../use-studio-panels";
import { LiveStatus } from "./live-status";

const descriptor = {
  label: "Check health",
  outputMode: "stream",
  argsSchema: {
    type: "object",
    properties: { app: { type: "string", enum: ["web", "api"] } },
    required: ["app"],
    additionalProperties: false,
  },
};
const revision = "a".repeat(64);
const panel = {
  module: "demo",
  id: "overview",
  enabled: true,
  type: "PANEL_TYPE_SPEC",
  fields: [],
  order: 0,
  title: "Overview",
  slot: "module",
  apps: {},
  uiReview: { revision },
  spec: {
    root: "health",
    elements: { health: { type: "StatusView", props: { action: "health", app: "web" } } },
  },
};
let project: string;
let client: Client<typeof ModuleService>;
let script: string;
vi.mock("@/lib/agent-provider", async (original) => ({
  ...(await original<typeof AgentProvider>()),
  useModuleServiceClient: () => client,
  useAgentContext: () => ({
    host: "localhost",
    port: 9876,
    selectedProjectId: project,
    isAuthenticated: true,
  }),
}));
vi.mock("@/lib/use-agent", () => ({
  useNixConfigQuery: () => ({
    data: {
      config: {
        modulesListAll: [
          {
            id: panel.module,
            enabled: true,
            meta: { name: "Demo" },
            actions: { health: { ...descriptor, script } },
          },
        ],
        panelsList: [panel],
      },
    },
  }),
}));
beforeEach(() => {
  project = "first-project";
  script = "check-health";
  descriptor.argsSchema.required = ["app"];
  panel.slot = "module";
  panel.uiReview = { revision };
});

function harness(
  options: {
    appId?: string;
    badGrant?: string;
    denyOnRun?: number;
    pauseOpen?: Promise<void>;
  } = {},
) {
  const opens: OpenModuleUIRequest[] = [];
  const runs: [string, unknown, string | null][] = [];
  const transport = createRouterTransport((router) =>
    router.service(ModuleService, {
      async openModuleUI(req, ctx) {
        opens.push(req);
        await options.pauseOpen;
        const failure = options.badGrant;
        if (failure !== "missing grant")
          ctx.responseHeader.set("X-Stackpanel-UI-Grant", `private-grant-${opens.length}`);
        const ttl = failure === "expired" ? -1 : failure === "unbounded expiry" ? 3602 : 300;
        ctx.responseHeader.set(
          "X-Stackpanel-UI-Expires-At",
          failure === "malformed expiry" ? "1e12" : String(Math.floor(Date.now() / 1000) + ttl),
        );
        return {
          reviewRevision:
            failure === "missing revision"
              ? ""
              : failure === "stale revision"
                ? "b".repeat(64)
                : req.reviewRevision,
          url: failure === "asset" ? "/frame.html" : "",
          settings: failure === "settings" ? {} : undefined,
          permissions: failure === "permission" ? ["config:read"] : ["actions:run"],
          actionIds:
            failure === "allowlist"
              ? []
              : failure === "extra id"
                ? ["health", "deploy"]
                : ["health"],
          actions: {
            ...(failure === "extra descriptor" ? { deploy: descriptor } : {}),
            health: {
              ...descriptor,
              label: failure === "changed metadata" ? "Different action" : descriptor.label,
              confirm: failure === "confirmation" ? "Approve this" : undefined,
            },
          },
        };
      },
      async *runModuleAction(req, ctx) {
        runs.push([req.actionId, req.args, ctx.requestHeader.get("X-Stackpanel-UI-Grant")]);
        if (runs.length === options.denyOnRun)
          throw new ConnectError("Grant revoked", Code.PermissionDenied);
        const target = req.args?.app ?? "module";
        if (typeof target !== "string")
          throw new ConnectError("Invalid target", Code.InvalidArgument);
        yield { event: { case: "stdout", value: `${target}: ready` } };
        yield { event: { case: "exitCode", value: 0 } };
      },
    }),
  );
  client = createClient(ModuleService, transport);
  const tree = (app?: string, appId = options.appId) => (
    <StrictMode>
      <TransportProvider transport={transport}>
        <StudioPanelsProvider>
          <LiveStatus
            moduleId="demo"
            panelId="overview"
            appId={appId}
            action="health"
            app={app}
            allowedApps={app === undefined ? [] : ["web", "api", "not-in-schema"]}
          />
        </StudioPanelsProvider>
      </TransportProvider>
    </StrictMode>
  );
  const view = render(tree("web"));
  const status = () => view.container.querySelector("sp-status-view");
  const shadow = () => status()!.shadowRoot!;
  function clickButton(text: RegExp) {
    const button = [...shadow().querySelectorAll("button")].find((b) =>
      text.test(b.textContent ?? ""),
    );
    if (!button) throw new Error(`No status button matching ${text}`);
    fireEvent.click(button);
  }
  return {
    ...view,
    select: (app?: string) => view.rerender(tree(app)),
    status,
    shadow,
    clickButton,
    opens,
    runs,
  };
}

it("does not discover, open, or run on mount/selection; one approval binds the selected args and grant", async () => {
  const h = harness();
  h.select("api");
  expect(h.opens).toHaveLength(0);
  expect(h.runs).toHaveLength(0);
  expect(h.container.textContent).toMatch(/first-project.*demo.*overview.*health.*api/s);
  expect(h.container.textContent).toContain("can contact the network");
  h.clickButton(/Load once/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("Last updated:"));
  expect(h.shadow().textContent).toContain("api: ready");
  expect(h.opens).toMatchObject([
    {
      moduleId: "demo",
      panelId: "overview",
      appId: "",
      reviewRevision: revision,
      statusAction: "health",
      statusApps: ["api"],
    },
  ]);
  expect(h.runs).toEqual([["health", { app: "api" }, "private-grant-1"]]);
  expect(h.container.innerHTML + h.shadow().innerHTML).not.toContain("private-grant");
  h.select("web");
  expect(h.shadow().textContent).not.toContain("api: ready");
  expect(h.runs).toHaveLength(1);
});

it("uses the original automatic grant and stops on agent rejection until the next human approval", async () => {
  const h = harness({ denyOnRun: 2 });
  expect(h.container.textContent).toContain("web, api");
  expect(h.container.textContent).not.toContain("not-in-schema");
  h.clickButton(/selection change|allow automatic/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("web: ready"));
  expect(h.opens).toMatchObject([
    { reviewRevision: revision, statusAction: "health", statusApps: ["web", "api"] },
  ]);
  h.select("api");
  await waitFor(() => expect(h.shadow().textContent).toMatch(/approve again/i));
  expect(h.shadow().textContent).toContain("Grant revoked");
  h.select("web");
  expect(h.opens).toHaveLength(1);
  expect(h.runs).toEqual([
    ["health", { app: "web" }, "private-grant-1"],
    ["health", { app: "api" }, "private-grant-1"],
  ]);
  h.clickButton(/Load once/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("web: ready"));
  expect(h.runs[2]).toEqual(["health", { app: "web" }, "private-grant-2"]);
});

it("refuses another selection after expiry even if the expiration timer has not fired", async () => {
  const h = harness();
  h.clickButton(/selection change|allow automatic/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("web: ready"));
  const clock = vi.spyOn(Date, "now").mockReturnValue(Date.now() + 301_000);
  try {
    h.select("api");
    await waitFor(() => expect(h.shadow().textContent).toMatch(/approve again/i));
    expect(h.opens).toHaveLength(1);
    expect(h.runs).toHaveLength(1);
  } finally {
    clock.mockRestore();
  }
});

it("sends an empty argument object only when an app is not required", async () => {
  const h = harness();
  h.select(undefined);
  expect(h.status()).toBeNull();
  descriptor.argsSchema.required = [];
  h.select(undefined);
  h.clickButton(/Load once/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("Last updated:"));
  expect(h.opens).toMatchObject([
    { reviewRevision: revision, statusAction: "health", statusApps: [] },
  ]);
  expect(h.runs).toEqual([["health", {}, "private-grant-1"]]);
});

it.each([
  "missing grant",
  "malformed expiry",
  "missing revision",
  "settings",
  "expired",
  "unbounded expiry",
  "asset",
  "allowlist",
  "permission",
  "confirmation",
  "changed metadata",
  "stale revision",
  "extra descriptor",
  "extra id",
])(
  "denies %s at initial grant acquisition, including on subsequent selections",
  async (badGrant) => {
    const h = harness({ badGrant });
    h.clickButton(/selection change|allow automatic/i);
    await waitFor(() => expect(h.shadow().textContent).toMatch(/approve again/i));
    h.select("api");
    h.select("web");
    expect(h.opens).toHaveLength(1);
    expect(h.runs).toHaveLength(0);
  },
);

it("requires a fresh review marker before presenting an actionable status view", async () => {
  panel.uiReview.revision = "invalid";
  const h = harness();
  expect(h.status()).toBeNull();
  panel.uiReview.revision = revision;
  h.select("web");
  h.clickButton(/selection change|allow automatic/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("web: ready"));
  panel.uiReview.revision = "b".repeat(64); // unchanged action ID and public metadata
  h.select("api");
  expect(h.shadow().textContent).not.toContain("web: ready");
  expect(h.runs).toHaveLength(1);
  expect(h.opens).toHaveLength(1);
});

it("ignores a delayed approval after a project change, and discards opt-in when evaluated authority changes", async () => {
  const { promise: pauseOpen, resolve: release } = Promise.withResolvers<void>();
  const h = harness({ pauseOpen });
  h.clickButton(/selection change|allow automatic/i);
  await waitFor(() => expect(h.opens).toHaveLength(1));
  project = "second-project";
  h.select("api");
  release();
  h.clickButton(/selection change|allow automatic/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("api: ready"));
  expect(h.runs).toEqual([["health", { app: "api" }, "private-grant-2"]]);
  script = "new-executable";
  h.select("web");
  expect(h.shadow().textContent).not.toContain("api: ready");
  expect(h.opens).toHaveLength(2);
  expect(h.runs).toHaveLength(1);
});

it("binds the route app at open and never offers an invalid or foreign app as actionable", async () => {
  panel.slot = "app:tab";
  const h = harness({ appId: "web" });
  h.clickButton(/selection change|allow automatic/i);
  await waitFor(() => expect(h.shadow().textContent).toContain("web: ready"));
  expect(h.opens).toMatchObject([{ appId: "web", statusApps: ["web"] }]);
  expect(h.container.textContent).not.toContain("web, api");
  for (const app of ["api", "", "undeclared"]) {
    h.select(app);
    expect(h.status()).toBeNull();
  }
  h.select("web");
  expect(h.shadow().textContent).not.toContain("web: ready");
  expect(h.opens).toHaveLength(1);
  expect(h.runs).toHaveLength(1);
});
