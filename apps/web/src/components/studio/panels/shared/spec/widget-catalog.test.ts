/// <reference types="vite-plus/test/globals" />
import { checkWidgetCatalog, widgetCatalog } from "./generate-widget-catalog";

it("keeps the checked-in author catalog in sync with Studio", () => {
  checkWidgetCatalog();
});

it("projects strict input props and their binding policies, not host grants", () => {
  const { components } = widgetCatalog();
  expect(components.StatusView.props).toMatchObject({
    type: "object",
    required: ["action"],
    additionalProperties: false,
  });
  expect(components.StatusView.props.properties).not.toHaveProperty("allowedApps");
  expect(components.StatusView.bindings).toEqual({ app: "local" });
  expect(components.AppPicker.bindings).toEqual({ apps: "data", value: "bindLocal" });
  expect(components.Metric.bindings).toEqual({ label: "read", value: "read" });
});

it("publishes hover text for every widget and prop, including table column fields", () => {
  const { components } = widgetCatalog();
  for (const widget of Object.values(components)) {
    expect(widget.description).toMatch(/\S/);
    for (const prop of Object.values(widget.props.properties!)) {
      expect(prop).toHaveProperty("description", expect.stringMatching(/\S/));
    }
  }
  expect(components.Table.props.properties?.columns).toMatchObject({
    items: {
      properties: {
        key: { description: expect.stringMatching(/\S/) },
        label: { description: expect.stringMatching(/\S/) },
      },
    },
  });
});
