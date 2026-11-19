/// <reference types="vite-plus/test/globals" />
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { PanelRenderer, FormPanelRenderer, StatusPanelRenderer } from "./panel-renderers";
import type { NixPanel, NixPanelField } from "./panel-types";

const mutate = vi.fn();
const mutateAsync = vi.fn(async () => {});
const config = {
  variables: { backend: "sops", "/var/API_URL": { value: "private-literal" } },
  serializable: {
    variables: { backend: "sops" },
    secrets: { variables: { "/dev/TOKEN": { file: "private-location" } } },
  },
  secrets: { backend: "sops", recipients: { deploy: { publicKey: "recipient-material" } } },
};
vi.mock("../modules/use-modules", () => ({ useModuleQueryScope: () => ["project"] }));
vi.mock("@/lib/use-agent", () => ({
  usePatchNixData: () => ({ mutate, mutateAsync, isPending: false }),
  useNixConfigQuery: () => ({ data: { config }, isLoading: false, isError: false }),
}));

const title: NixPanelField = {
  name: "title",
  type: "FIELD_TYPE_STRING",
  label: "Display name",
  value: "Original",
  editable: true,
  configPath: "build.title",
  editPath: "build.title",
};
const targets: NixPanelField = {
  name: "targets",
  type: "FIELD_TYPE_MULTISELECT",
  label: "Targets",
  value: '["node"]',
  options: ["node", { value: "cf", label: "Workers" }],
  editable: true,
  configPath: "build.targets",
  editPath: "build.targets",
};
const credential: NixPanelField = {
  name: "credential",
  type: "FIELD_TYPE_SECRET_REF",
  label: "Credential",
  value: "untrusted-old-value",
  editable: true,
  configPath: "build.credential",
  editPath: "build.credential",
};
const notes: NixPanelField = {
  name: "notes",
  type: "FIELD_TYPE_MARKDOWN",
  value: "## Setup notes",
};
const panel: NixPanel = {
  id: "build",
  module: "build",
  slot: "module",
  type: "PANEL_TYPE_FORM",
  title: "Build settings",
  order: 0,
  enabled: true,
  fields: [title, targets, credential, notes],
  apps: { web: { enabled: true, config: { title: "App value", targets: '["node"]' } } },
};

function renderAppSettings(panel: NixPanel) {
  return (
    <PanelRenderer
      panel={{ ...panel, slot: "app:tab", type: "PANEL_TYPE_APP_CONFIG" }}
      panels={[]}
      appId="web"
    />
  );
}

it("keeps per-app typing local until blur and resyncs a draft when evaluation changes", () => {
  const { rerender } = render(renderAppSettings(panel));
  const input = screen.getByRole<HTMLInputElement>("textbox", { name: "Display name" });
  expect(input.value).toBe("App value");
  fireEvent.change(input, { target: { value: "Release" } });
  expect(input.value).toBe("Release");
  expect(mutate).not.toHaveBeenCalled();
  fireEvent.blur(input);
  expect(mutate).toHaveBeenCalledWith({
    entity: "apps",
    key: "web",
    path: "build.title",
    valueType: "string",
    value: '"Release"',
  });
  fireEvent.change(input, { target: { value: "Never submitted" } });
  const refreshed = {
    ...panel,
    fields: [{ ...title, editable: false }],
    apps: { web: { enabled: true, config: { title: "From evaluation" } } },
  };
  rerender(renderAppSettings(refreshed));
  const next = screen.getByRole<HTMLInputElement>("textbox", { name: "Display name" });
  expect(next.value).toBe("From evaluation");
  expect(next.disabled).toBe(true);
  fireEvent.blur(next);
  expect(mutate).toHaveBeenCalledTimes(1);
});

it("uses the declared multiselect labels and sends the complete selected value list", () => {
  const { rerender } = render(renderAppSettings(panel));
  expect(screen.getByRole("checkbox", { name: "node" }).getAttribute("aria-checked")).toBe("true");
  fireEvent.click(screen.getByRole("checkbox", { name: "Workers" }));
  expect(mutate).toHaveBeenLastCalledWith({
    entity: "apps",
    key: "web",
    path: "build.targets",
    valueType: "list",
    value: '["node","cf"]',
  });
  const refreshed = { ...panel, apps: { web: { enabled: true, config: { targets: '["cf"]' } } } };
  rerender(renderAppSettings(refreshed));
  expect(screen.getByRole("checkbox", { name: "node" }).getAttribute("aria-checked")).toBe("false");
  fireEvent.click(screen.getByRole("checkbox", { name: "Workers" }));
  expect(mutate).toHaveBeenLastCalledWith(
    expect.objectContaining({ value: "[]", valueType: "list" }),
  );
  expect(screen.getByRole("heading", { name: "Setup notes" })).toBeTruthy();
});

it("saves a form's list and reference key without exposing secret values or backend settings", async () => {
  const { container } = render(<FormPanelRenderer panel={panel} />);
  const select = screen.getByRole<HTMLSelectElement>("combobox", { name: "Credential" });
  expect(Array.from(select.options, (option) => option.value)).toEqual([
    "",
    "/dev/TOKEN",
    "/var/API_URL",
  ]);
  expect(container.innerHTML).not.toMatch(
    /private-literal|private-location|recipient-material|untrusted-old-value/,
  );
  fireEvent.change(select, { target: { value: "/dev/TOKEN" } });
  fireEvent.click(screen.getByRole("checkbox", { name: "Workers" }));
  expect(mutateAsync).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "Save Changes" }));
  await screen.findByText("No changes");
  expect(mutateAsync).toHaveBeenCalledWith({
    entity: "config",
    key: "_root",
    path: "stackpanel.build.targets",
    valueType: "list",
    value: '["node","cf"]',
  });
  expect(mutateAsync).toHaveBeenCalledWith({
    entity: "config",
    key: "_root",
    path: "stackpanel.build.credential",
    valueType: "string",
    value: '"/dev/TOKEN"',
  });
  expect(select.value).toBe("/dev/TOKEN");
});

it("refreshes changed form values without discarding an unrelated unsaved selection", async () => {
  const { rerender } = render(<FormPanelRenderer panel={panel} />);
  fireEvent.click(screen.getByRole("checkbox", { name: "Workers" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Display name" }), {
    target: { value: "Draft" },
  });
  rerender(
    <FormPanelRenderer panel={{ ...panel, fields: [{ ...title, value: "Updated" }, targets] }} />,
  );
  expect(screen.getByRole<HTMLInputElement>("textbox", { name: "Display name" }).value).toBe(
    "Updated",
  );
  expect(screen.getByRole("checkbox", { name: "Workers" }).getAttribute("aria-checked")).toBe(
    "true",
  );
  fireEvent.click(screen.getByRole("button", { name: "Save Changes" }));
  await waitFor(() => expect(mutateAsync).toHaveBeenCalledTimes(1));
  expect(mutateAsync).toHaveBeenCalledWith(
    expect.objectContaining({ path: "stackpanel.build.targets", value: '["node","cf"]' }),
  );
});

it("renders status Markdown, selected labels and validated reference keys without editing controls", () => {
  const status = {
    ...panel,
    type: "PANEL_TYPE_STATUS",
    fields: [notes, { ...targets, value: '["cf"]' }, credential],
  };
  const { container, rerender } = render(<StatusPanelRenderer panel={status} />);
  expect(screen.getByRole("heading", { name: "Setup notes" })).toBeTruthy();
  expect(screen.getByText("Workers")).toBeTruthy();
  expect(screen.getByText("Reference unavailable")).toBeTruthy();
  expect(screen.queryByRole("combobox")).toBeNull();
  expect(container.innerHTML).not.toContain("untrusted-old-value");
  rerender(
    <StatusPanelRenderer
      panel={{ ...status, fields: [{ ...credential, value: "/var/API_URL" }] }}
    />,
  );
  expect(screen.getByText("/var/API_URL")).toBeTruthy();
  expect(container.innerHTML).not.toContain("private-literal");
});
