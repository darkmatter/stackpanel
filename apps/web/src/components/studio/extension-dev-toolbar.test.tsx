import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { expect, it, vi } from "vite-plus/test";
import { ExtensionDevToolsProvider, useExtensionDevTools } from "./extension-dev-toolbar";

const fixture = vi.hoisted(() => ({
  onDiagnostics: undefined as ((event: { data: unknown }) => void) | undefined,
  scope: ["agent", "modules", "localhost", 9876, "shop", null],
  catalog: {
    modules: [{ id: "sample", linked: true, uiDevUrl: "http://localhost:5173/private-path" }],
  },
}));
vi.mock("@/lib/agent-provider", () => ({
  useAgentContext: () => ({
    selectedProjectId: "shop",
    host: "localhost",
    port: 9876,
    isAuthenticated: true,
  }),
}));
vi.mock("@/lib/agent-sse-provider", () => ({
  useAgentSSEOptional: () => ({
    addEventListener: (_event: string, listener: typeof fixture.onDiagnostics) => {
      fixture.onDiagnostics = listener;
      return () => {
        fixture.onDiagnostics = undefined;
      };
    },
  }),
}));
vi.mock("./panels/modules/use-modules", () => ({
  useModuleCatalog: () => ({ data: fixture.catalog }),
  useModuleQueryScope: () => fixture.scope,
}));

function PanelProbe() {
  const dev = useExtensionDevTools();
  return (
    <button
      type="button"
      onClick={() =>
        dev?.audit({
          id: 1,
          moduleId: "sample",
          panelId: "custom",
          method: "proxyFetch",
          outcome: "denied",
        })
      }
    >
      Probe {dev?.revision.get("sample") ?? 0}
    </button>
  );
}

it("shows current-project eval latency and errors, logs permission decisions, and reopens linked panels", async () => {
  const cache = new QueryClient();
  const refresh = vi.spyOn(cache, "invalidateQueries");
  render(
    <QueryClientProvider client={cache}>
      <ExtensionDevToolsProvider>
        <PanelProbe />
      </ExtensionDevToolsProvider>
    </QueryClientProvider>,
  );
  fireEvent.click(screen.getByText("Extension development · sample"));
  expect(screen.getByText("HMR: http://localhost:5173")).toBeTruthy();
  expect(screen.queryByText(/private-path/)).toBeNull();
  const data = {
    linkedModules: { sample: { uiDevUrl: "http://localhost:5173/" } },
    durationMs: 81,
  };
  act(() =>
    fixture.onDiagnostics?.({ data: { ...data, projectId: "other", error: "foreign error" } }),
  );
  expect(screen.queryByText("foreign error")).toBeNull();
  act(() =>
    fixture.onDiagnostics?.({ data: { ...data, projectId: "shop", error: "Evaluation failed" } }),
  );
  expect(screen.getByText("Nix evaluation: 81 ms")).toBeTruthy();
  expect(screen.getByText("Evaluation failed")).toBeTruthy();
  fireEvent.click(screen.getByText("Probe 0"));
  fireEvent.click(screen.getByText("SDK permission log"));
  expect(screen.getByText("custom: proxyFetch — denied")).toBeTruthy();
  fireEvent.click(screen.getByText("Reload Module"));
  await waitFor(() => expect(screen.getByText("Probe 1")).toBeTruthy());
  expect(refresh).toHaveBeenCalledWith({ queryKey: fixture.scope }, { throwOnError: true });
  act(() => fixture.onDiagnostics?.({ data: { ...data, projectId: "shop", linkedModules: {} } }));
  expect(screen.queryByLabelText("Extension development")).toBeNull();
});
