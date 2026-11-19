import { z } from "zod";

export const limits = { maxElements: 64, maxDepth: 16 } as const;

const keyPattern = /^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$/;
export const safeKey = (key: string) =>
  keyPattern.test(key) && key !== "prototype" && !Object.hasOwn(Object.prototype, key);
export const id = z.string().refine(safeKey, "Expected a safe identifier (1–128 characters).");

// Target IDs travel as string values, not as JSON pointers or URL segments.
const targetPattern = /^[^\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]{1,128}$/u;
export function isPanelTargetId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    targetPattern.test(value) &&
    value.trim() === value &&
    value !== "prototype" &&
    !Object.hasOwn(Object.prototype, value)
  );
}
const targetId = z
  .string()
  .refine(isPanelTargetId, "Expected a safe app or action ID (1–128 Unicode code points).");
const text = z.string().max(4096);
const cell = z.union([text, z.number(), z.boolean(), z.null()]);
const rows = z.array(z.record(id, cell)).max(128);
const apps = z
  .array(targetId)
  .max(128)
  .refine((values) => new Set(values).size === values.length, "Duplicate app id.");

export const panelState = z.strictObject({
  data: z
    .record(id, z.union([cell, rows, apps]))
    .optional()
    .describe("Read-only values available to widgets at /data/<key>."),
  local: z
    .record(id, text)
    .optional()
    .describe("Initial string values for local bindings at /local/<key>."),
});

const selectedApp = z.union([z.literal(""), targetId]);
const columns = z
  .array(
    z.strictObject({
      key: id.describe("Field to read from each row. Each column needs a distinct key."),
      label: text.describe("Heading shown above this column."),
    }),
  )
  .min(1)
  .max(16)
  .refine(
    (list) => new Set(list.map((col) => col.key)).size === list.length,
    "Duplicate column key.",
  );

// Omitted props are literal-only. Read modes also allow literals; bindLocal
// requires a writable reference, not a literal or a one-way read.
type BindingMode = "read" | "data" | "local" | "bindLocal";
function component<T extends z.ZodRawShape>(
  description: string,
  shape: T,
  bindings: Partial<Record<keyof NoInfer<T> & string, BindingMode>> = {},
  container = false,
) {
  const modes: Readonly<Partial<Record<string, BindingMode>>> = bindings;
  return {
    description,
    props: z.strictObject(shape),
    bindings: modes,
    slots: container ? ["default"] : [],
  };
}

const statusView = component(
  "Show live status from a reviewed read action on the panel's owning module.",
  {
    action: targetId.describe("ID of the owner's status action to read."),
    app: selectedApp
      .optional()
      .describe(
        "Target app ID, or a local selection written by an AppPicker. Omit for a module-level read.",
      ),
  },
  { app: "local" },
);

export const components = {
  Stack: component(
    "Arrange child widgets in a column or a row.",
    {
      direction: z
        .enum(["vertical", "horizontal"])
        .optional()
        .describe("Layout direction for the children. Defaults to vertical."),
    },
    {},
    true,
  ),
  Section: component(
    "Group child widgets under a heading.",
    { title: text.describe("Heading shown above the child widgets.") },
    { title: "read" },
    true,
  ),
  Text: component(
    "Display a paragraph of plain text.",
    { content: text.describe("Text to display, preserving line breaks.") },
    { content: "read" },
  ),
  Badge: component(
    "Display a short label as a badge.",
    { text: text.describe("Text shown inside the badge.") },
    { text: "read" },
  ),
  Metric: component(
    "Display a single value with a caption.",
    {
      label: text.describe("Caption shown above the metric."),
      value: z.union([text, z.number()]).describe("Number or text shown as the metric value."),
    },
    { label: "read", value: "read" },
  ),
  Table: component(
    "Display records in a table with ordered columns.",
    {
      columns: columns.describe("Columns to display, in order from left to right."),
      rows: rows.describe(
        "Records to display. Each column key selects a text, number, boolean or null cell.",
      ),
    },
    { rows: "read" },
  ),
  Actions: component("Show action controls for the panel's owning module.", {
    ids: z
      .array(targetId)
      .max(32)
      .optional()
      .describe(
        "IDs of owner actions to show. Omit to show all, or use an empty list to show none.",
      ),
  }),
  AppPicker: component(
    "Let the operator select an app and write its ID to local state.",
    {
      apps: apps.describe("Distinct app IDs to offer, as a list or a read from /data/<key>."),
      value: selectedApp.describe(
        "Writable /local/<key> binding. Initialize it to an offered app ID or the empty string.",
      ),
      label: text.optional().describe("Label shown with the picker. Defaults to App."),
    },
    { apps: "data", value: "bindLocal" },
  ),
  StatusView: {
    ...statusView,
    // Output-only. The author schema stays strict; a bound app gets its
    // picker's checked choices after the whole document has parsed.
    props: statusView.props.transform((props) => ({
      ...props,
      allowedApps: props.app === undefined ? [] : [props.app],
    })),
  },
};
