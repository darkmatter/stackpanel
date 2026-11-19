/// <reference types="vite-plus/test/globals" />
import { fireEvent, render, screen } from "@testing-library/react";
import { ModuleConfigForm } from "./module-config-form";

const mutate = vi.fn();
vi.mock("./use-modules", () => ({
  useSaveModuleConfig: () => ({ mutate, reset: vi.fn(), isPending: false, error: null }),
}));
beforeEach(() => {
  mutate.mockClear();
});

it("sends only changed relative settings and keeps enum value types and literal dotted keys", () => {
  const schema = JSON.stringify({
    type: "object",
    properties: { "runtime.count": { enum: [1, 2] }, enabled: { type: "boolean" } },
  });
  render(
    <ModuleConfigForm
      moduleId="builder"
      schema={schema}
      settings={{ "runtime.count": 1, enabled: false }}
      onChanged={vi.fn()}
    />,
  );
  fireEvent.change(screen.getByRole("combobox", { name: "runtime.count" }), {
    target: { value: "2" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save Changes" }));
  expect(mutate).toHaveBeenCalledTimes(1);
  expect(mutate.mock.calls[0]?.[0]).toEqual({ "runtime.count": 2 });
});

it("does not submit invalid JSON or overwrite a newer evaluated setting with a stale draft", () => {
  const onChanged = vi.fn();
  const { rerender } = render(
    <ModuleConfigForm moduleId="builder" settings={{ mode: "auto" }} onChanged={onChanged} />,
  );
  const input = screen.getByRole<HTMLTextAreaElement>("textbox", { name: "Module settings JSON" });
  const save = screen.getByRole<HTMLButtonElement>("button", { name: "Save Changes" });
  fireEvent.change(input, { target: { value: "[" } });
  expect(screen.getByRole("alert")).toBeTruthy();
  expect(save.disabled).toBe(true);
  fireEvent.change(input, { target: { value: '{"mode":"debug"}' } });
  expect(save.disabled).toBe(false);
  rerender(
    <ModuleConfigForm moduleId="builder" settings={{ mode: "release" }} onChanged={onChanged} />,
  );
  expect(screen.getByRole("alert").textContent).toContain("Settings changed in the project");
  expect(save.disabled).toBe(true);
  fireEvent.click(screen.getByRole("button", { name: "Discard draft" }));
  expect(JSON.parse(input.value)).toEqual({ mode: "release" });
  expect(mutate).not.toHaveBeenCalled();
});
