import { render, screen } from "@testing-library/react";
import { expect, it, vi } from "vite-plus/test";
import { PanelsPanel } from "./panels-panel";
import type { NixPanel } from "./shared/panel-types";
import { StudioPanelsProvider } from "./shared/use-studio-panels";

const state = vi.hoisted(() => ({ config: {} as Record<string, unknown> }));
vi.mock("@/lib/use-agent", () => ({
  useNixConfigQuery: () => ({ data: { config: state.config }, isLoading: false, error: null }),
}));
vi.mock("./modules/use-modules", () => ({ useModuleQueryScope: () => ["fixture"] }));

function panel(id: string, attrs: Partial<NixPanel> = {}): NixPanel {
  return {
    id,
    title: id,
    type: "PANEL_TYPE_STATUS",
    module: "search",
    slot: "module",
    enabled: true,
    order: 0,
    fields: [],
    apps: {},
    ...attrs,
  };
}

it("mounts only enabled module-slot panels for the chosen module, including nested tabs", () => {
  state.config = {
    modulesListAll: [
      { id: "search", enabled: true, meta: { name: "Search tools" }, actions: {} },
      { id: "cloud", enabled: true, meta: { name: "Cloud tools" }, actions: {} },
      { id: "retired", enabled: false, meta: { name: "Retired tools" }, actions: {} },
    ],
    panelsList: [
      panel("Catalog", { type: "PANEL_TYPE_TABS", tabs: ["Index", "Widget", "Other", "Disabled"] }),
      panel("Index"),
      panel("Widget", { slot: "overview" }),
      panel("Other", { module: "cloud" }),
      panel("Disabled", { enabled: false }),
      panel("Old config", { module: "retired" }),
    ],
  };
  const view = (moduleId: string) => (
    <StudioPanelsProvider>
      <PanelsPanel moduleId={moduleId} />
    </StudioPanelsProvider>
  );
  const { rerender } = render(view("search"));
  expect(screen.getByText("Search tools")).toBeTruthy();
  expect(screen.getAllByRole("tab").map((tab) => tab.textContent)).toEqual(["Index"]);
  // One tab trigger and one child panel, not a duplicate standalone panel.
  expect(screen.getAllByText("Index")).toHaveLength(2);
  expect(screen.queryByText("Widget")).toBeNull();
  expect(screen.queryByText("Other")).toBeNull();
  rerender(view("cloud"));
  expect(screen.queryByText("Catalog")).toBeNull();
  expect(screen.getByText("Other")).toBeTruthy();
  rerender(view("retired"));
  expect(screen.queryByText("Old config")).toBeNull();
  expect(screen.getByText("No module panels for retired.")).toBeTruthy();
});

it("reports incomplete evaluated state rather than mounting a panel with inferred scope", () => {
  const { apps: _, ...incomplete } = panel("Restricted");
  state.config = {
    modulesListAll: [{ id: "search", enabled: true, meta: { name: "Search tools" }, actions: {} }],
    panelsList: [incomplete],
  };
  render(<StudioPanelsProvider><PanelsPanel moduleId="search" /></StudioPanelsProvider>);
  expect(screen.getByRole("alert").textContent).toMatch(/incomplete panel descriptor/i);
  expect(screen.queryByText("Restricted")).toBeNull();
});
