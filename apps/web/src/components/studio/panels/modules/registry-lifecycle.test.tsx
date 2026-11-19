// @vitest-environment jsdom
import { toJson } from "@bufbuild/protobuf";
import { ValueSchema } from "@bufbuild/protobuf/wkt";
import {
  Code,
  ConnectError,
  createClient,
  createRouterTransport,
  type Client,
} from "@connectrpc/connect";
import { TransportProvider } from "@connectrpc/connect-query";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { ShellService } from "@stackpanel/proto/agent/v1/shell";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  act,
  fireEvent,
  render,
  renderHook,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { beforeEach, expect, it, vi } from "vitest";
import { RegistryBrowser } from "./registry-browser";
import { ModulesPanel } from "./modules-panel";
import { AdoptionPreviewDialog } from "./adoption-preview-dialog";
import { useInstallModule, useModule, useModuleOutputs, useRegistryModule } from "./use-modules";

let client: Client<typeof ModuleService>;
let project: string | null = "storefront";
vi.mock("@/lib/agent-provider", () => ({
  useAgentContext: () => ({
    host: "localhost",
    port: 9876,
    selectedProjectId: project,
    isConnected: true,
    isAuthenticated: true,
  }),
  useModuleServiceClient: () => client,
}));

function registryEntry(name: string) {
  return {
    id: "reports",
    slug: "reports",
    name,
    latestVersion: "2",
    versions: [
      { version: "1", flakeUrl: "github:team/modules?dir=reports", ref: "release-1" },
      {
        version: "2",
        flakeUrl: "github:team/modules?dir=reports",
        ref: "release-2",
        followsNixpkgs: true,
      },
    ],
  };
}

const makeCache = () => new QueryClient({ defaultOptions: { queries: { retry: false } } });
const reportsModule = {
  id: "reports",
  enabled: false,
  meta: { name: "Reports" },
  source: { type: "registry" },
  features: {},
  settings: {},
};
beforeEach(() => {
  project = "storefront";
});

it("keeps the locked version on update errors and offers rebuild only after a write succeeds", async () => {
  let installed = true;
  let version = "1";
  let rejectUpdate = true;
  const entry = () => ({
    ...registryEntry("Reports"),
    installed,
    installedVersion: installed ? version : undefined,
  });
  const transport = createRouterTransport((router) => {
    router.service(ModuleService, {
      listRegistryModules: () => ({ modules: [entry()] }),
      getRegistryModule: () => ({ module: entry() }),
      getModule: () => ({ module: reportsModule }),
      updateModule(request) {
        if (rejectUpdate) throw new ConnectError("cannot lock this ref", Code.FailedPrecondition);
        version = request.version;
        return { message: "Updated reports" };
      },
      uninstallModule() {
        installed = false;
        return { message: "Removed reports" };
      },
    });
    router.service(ShellService, {
      async *rebuildShell() {
        yield { event: { case: "completed", value: { exitCode: 2 } } };
      },
    });
  });
  client = createClient(ModuleService, transport);
  render(
    <QueryClientProvider client={makeCache()}>
      <TransportProvider transport={transport}>
        <RegistryBrowser />
      </TransportProvider>
    </QueryClientProvider>,
  );
  fireEvent.click(await screen.findByRole("button", { name: "View Details" }));
  const drawer = within(await screen.findByRole("dialog"));
  fireEvent.click(await drawer.findByText("Manual setup · flake.nix"));
  fireEvent.change(drawer.getByLabelText("Git ref"), { target: { value: "feature/reports" } });
  expect(
    drawer.getByDisplayValue(/github:team\/modules\/feature\/reports\?dir=reports/),
  ).toBeTruthy();
  fireEvent.change(drawer.getByLabelText("Git ref"), { target: { value: "" } });
  fireEvent.click(await drawer.findByRole("button", { name: "Update" }));
  expect(await drawer.findByText(/cannot lock this ref/)).toBeTruthy();
  expect(drawer.getByText("Locked version: 1")).toBeTruthy();
  expect(drawer.queryByRole("button", { name: "Rebuild shell" })).toBeNull();
  rejectUpdate = false;
  fireEvent.click(drawer.getByRole("button", { name: "Update" }));
  expect(await drawer.findByText("Locked version: 2")).toBeTruthy();
  fireEvent.click(await drawer.findByRole("button", { name: "Rebuild shell" }));
  expect(await drawer.findByText("Shell rebuild exited with code 2.")).toBeTruthy();
  fireEvent.click(drawer.getByRole("button", { name: "Uninstall" }));
  fireEvent.click(drawer.getByRole("button", { name: "Confirm uninstall" }));
  expect(await drawer.findByRole("button", { name: "Install" })).toBeTruthy();
  expect(drawer.queryByText(/Locked version/)).toBeNull();
});

it("does not show the previous project's registry while the new project's response is in flight", async () => {
  const transport = createRouterTransport((router) =>
    router.service(ModuleService, {
      listRegistryModules() {
        return { modules: [registryEntry(`${project} report`)] };
      },
    }),
  );
  client = createClient(ModuleService, transport);
  const cache = makeCache();
  const tab = () => (
    <QueryClientProvider client={cache}>
      <TransportProvider transport={transport}>
        <RegistryBrowser />
      </TransportProvider>
    </QueryClientProvider>
  );
  const view = render(tab());
  expect(await screen.findByText("storefront report")).toBeTruthy();
  project = "api";
  view.rerender(tab());
  expect(screen.queryByText("storefront report")).toBeNull();
  expect(await screen.findByText("api report")).toBeTruthy();
});

it("withholds unpinned RPCs and discards an enable approval on a project switch", async () => {
  const requested: string[] = [];
  const enable = vi.fn(() => ({ message: "Enabled" }));
  const entry = () => ({ ...registryEntry(`${project} report`), installed: true });
  const transport = createRouterTransport((router) =>
    router.service(ModuleService, {
      listRegistryModules() {
        requested.push(project ?? "none");
        return { modules: [entry()] };
      },
      getRegistryModule: () => ({ module: entry() }),
      getModule: () => ({ module: reportsModule }),
      previewModuleEnable: () => ({
        preview: { files: { added: [`${project}/report.json`] }, packages: {}, services: {} },
      }),
      enableModule: enable,
    }),
  );
  client = createClient(ModuleService, transport);
  const cache = makeCache();
  const tab = () => (
    <QueryClientProvider client={cache}>
      <TransportProvider transport={transport}>
        <ModulesPanel />
      </TransportProvider>
    </QueryClientProvider>
  );
  project = null;
  const view = render(tab());
  expect(await screen.findByText(/select a project to manage its modules/i)).toBeTruthy();
  expect(requested).toEqual([]);
  project = "storefront";
  view.rerender(tab());
  fireEvent.click(await screen.findByRole("button", { name: "View Details" }));
  fireEvent.click(await screen.findByRole("button", { name: "Enable" }));
  expect(await screen.findByText("storefront/report.json")).toBeTruthy();
  project = "api";
  view.rerender(tab());
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(await screen.findByText("api report")).toBeTruthy();
  expect(enable).not.toHaveBeenCalled();
});

it("re-previews only explicit select and multiselect answers and commits the displayed revisions", async () => {
  const enabled = vi.fn();
  const offers = [
    {
      id: "language",
      label: "Language",
      revision: "3",
      type: "select",
      choices: [{ label: "Go", value: "go" }],
    },
    {
      id: "tools",
      label: "Tools",
      revision: "8",
      type: "multiselect",
      choices: [{ label: "Formatter", value: "fmt" }],
    },
  ];
  const transport = createRouterTransport((router) =>
    router.service(ModuleService, {
      getModule: () => ({ module: reportsModule }),
      previewModuleEnable({ answers }) {
        const selected = answers.map(({ answer }) =>
          JSON.stringify(answer && toJson(ValueSchema, answer)),
        );
        return {
          preview: {
            offers,
            files: { added: [selected.join(" + ") || "No choices"] },
            packages: {},
            services: {},
          },
        };
      },
      enableModule({ answers }) {
        enabled(
          answers.map(({ id, revision, answer }) => [
            id,
            revision,
            answer && toJson(ValueSchema, answer),
          ]),
        );
        return { message: "Enabled reports" };
      },
    }),
  );
  client = createClient(ModuleService, transport);
  render(
    <QueryClientProvider client={makeCache()}>
      <TransportProvider transport={transport}>
        <AdoptionPreviewDialog moduleId="reports" onClose={() => {}} onEnabled={() => {}} />
      </TransportProvider>
    </QueryClientProvider>,
  );
  expect(await screen.findByText("No choices")).toBeTruthy();
  fireEvent.change(screen.getByRole("combobox", { name: "Language" }), { target: { value: "0" } });
  fireEvent.click(screen.getByRole("checkbox", { name: "Formatter" }));
  expect(await screen.findByText('"go" + ["fmt"]')).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "Leave undecided" }));
  expect(await screen.findByText('"go"')).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "Decline all" }));
  expect(await screen.findByText('"go" + []')).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "Enable" }));
  await vi.waitFor(() =>
    expect(enabled).toHaveBeenCalledWith([
      ["language", "3", "go"],
      ["tools", "8", []],
    ]),
  );
});

it.each(["files", "packages", "services"] as const)(
  "does not enable from a plan missing its %s diff",
  async (missing) => {
    const enable = vi.fn(() => ({ message: "Enabled" }));
    const transport = createRouterTransport((router) =>
      router.service(ModuleService, {
        getModule: () => ({ module: reportsModule }),
        previewModuleEnable: () => ({
          preview: { files: {}, services: {}, packages: {}, [missing]: undefined },
        }),
        enableModule: enable,
      }),
    );
    client = createClient(ModuleService, transport);
    render(
      <QueryClientProvider client={makeCache()}>
        <TransportProvider transport={transport}>
          <AdoptionPreviewDialog moduleId="reports" onClose={() => {}} onEnabled={() => {}} />
        </TransportProvider>
      </QueryClientProvider>,
    );
    expect((await screen.findByRole("alert")).textContent).toContain(
      "Incomplete enable plan for reports",
    );
    const button = screen.getByRole<HTMLButtonElement>("button", { name: "Enable" });
    expect(button.disabled).toBe(true);
    fireEvent.click(button);
    expect(enable).not.toHaveBeenCalled();
  },
);

it("rejects foreign detail, outputs, registry and install targets instead of accepting them as reports", async () => {
  const transport = createRouterTransport((router) =>
    router.service(ModuleService, {
      getModule: () => ({ module: { ...reportsModule, id: "other" } }),
      getModuleOutputs: () => ({ outputs: { moduleId: "other" } }),
      getRegistryModule: () => ({ module: { ...registryEntry("Other"), slug: "other" } }),
      installModule: () => ({ moduleId: "other" }),
    }),
  );
  client = createClient(ModuleService, transport);
  const cache = makeCache();
  const { result } = renderHook(
    () => ({
      detail: useModule("reports"),
      outputs: useModuleOutputs("reports"),
      registry: useRegistryModule("reports"),
      install: useInstallModule(),
    }),
    {
      wrapper: ({ children }) => (
        <QueryClientProvider client={cache}>
          <TransportProvider transport={transport}>{children}</TransportProvider>
        </QueryClientProvider>
      ),
    },
  );
  await waitFor(() => {
    for (const query of [result.current.detail, result.current.outputs, result.current.registry]) {
      expect(query.error?.message).toContain("reports");
      expect(query.data).toBeUndefined();
    }
  });
  await act(async () => {
    await expect(
      result.current.install.mutateAsync({ moduleId: "reports", version: "1", ref: "" }),
    ).rejects.toThrow("did not confirm installation of reports");
  });
});
