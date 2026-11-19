/// <reference types="vite-plus/test/globals" />
import { parsePanelSpec } from "./catalog";

const actions = { type: "Actions", props: { ids: ["deploy", "scale"] } };
const text = { type: "Text", props: { content: "Status" } };
const table = { columns: [{ key: "id", label: "ID" }], rows: [{ id: 1 }] };
const data = { title: "Workers", workers: table.rows };

function group(children: string[], elements: Record<string, unknown>) {
  return { root: "root", elements: { root: { type: "Stack", props: {}, children }, ...elements } };
}

it("distinguishes an explicit list of capabilities, all owner actions and a display-only spec", () => {
  const doc = group(["a", "b"], {
    a: actions,
    b: { type: "Actions", props: { ids: ["scale", "stop"] } },
  });
  expect(parsePanelSpec(doc)).toMatchObject({ ok: true, actionIds: ["deploy", "scale", "stop"] });
  expect(
    parsePanelSpec(group(["a", "b"], { a: actions, b: { type: "Actions", props: {} } })),
  ).toMatchObject({ ok: true, actionIds: "all" });
  expect(
    parsePanelSpec(group(["t", "a"], { t: text, a: { type: "Actions", props: { ids: [] } } })),
  ).toMatchObject({ ok: true, actionIds: [] });
});

const picker = {
  type: "AppPicker",
  props: { apps: { $state: "/data/appIds" }, value: { $bindState: "/local/app" } },
};
const status = { type: "StatusView", props: { action: "status", app: { $state: "/local/app" } } };
const selection = { data: { appIds: ["worker"] }, local: { app: "worker" } };

it("includes live reads in the deduplicated owner action list", () => {
  const doc = group(["s", "p", "a"], {
    p: picker,
    s: status,
    a: { type: "Actions", props: { ids: ["status", "stop"] } },
  });
  expect(parsePanelSpec({ ...doc, state: selection })).toMatchObject({
    ok: true,
    actionIds: ["status", "stop"],
  });
});

it("preserves owner app and action IDs as string values rather than route segments", () => {
  const action = "_查詢/status";
  const doc = group(["picker", "status", "controls"], {
    picker,
    status: { ...status, props: { ...status.props, action } },
    controls: { type: "Actions", props: { ids: [action] } },
  });
  const state = { local: { app: "_api" }, data: { appIds: ["_api", "service two"] } };
  expect(parsePanelSpec({ ...doc, state })).toMatchObject({
    ok: true,
    actionIds: [action],
    spec: { elements: { status: { props: { allowedApps: state.data.appIds } } } },
  });
});

it.each([
  [
    "write outside local state",
    { ...picker, props: { ...picker.props, value: { $bindState: "/app/id" } } },
    status,
    selection,
  ],
  ["uninitialized selection", picker, status, { data: selection.data }],
  ["initial value outside the list", picker, status, { ...selection, local: { app: "other" } }],
  ["untyped options", picker, status, { ...selection, data: { appIds: table.rows } }],
  ["missing picker binding", { ...picker, props: { apps: ["worker"] } }, text, selection],
  [
    "literal picker value",
    { ...picker, props: { ...picker.props, value: "worker" } },
    text,
    selection,
  ],
  [
    "picker options from outside public data",
    { ...picker, props: { ...picker.props, apps: { $state: "/local/app" } } },
    status,
    selection,
  ],
  [
    "read instead of writable picker value",
    { ...picker, props: { ...picker.props, value: { $state: "/local/app" } } },
    status,
    selection,
  ],
  [
    "write from a display prop",
    picker,
    { type: "Text", props: { content: { $bindState: "/local/app" } } },
    selection,
  ],
  [
    "bound action",
    picker,
    { ...status, props: { ...status.props, action: { $state: "/local/app" } } },
    selection,
  ],
  [
    "ambient app as a status selector",
    picker,
    { ...status, props: { action: "status", app: { $state: "/app/id" } } },
    selection,
  ],
  [
    "status targeting another module",
    picker,
    { ...status, props: { ...status.props, moduleId: "other" } },
    selection,
  ],
  [
    "status with arbitrary arguments",
    picker,
    { ...status, props: { ...status.props, args: { app: "other" } } },
    selection,
  ],
  [
    "author-supplied grant targets",
    picker,
    { ...status, props: { ...status.props, allowedApps: ["other"] } },
    selection,
  ],
  ["selection without a picker", text, status, selection],
  ["two writers for one selection", picker, picker, selection],
])("rejects %s before authorizing any controls", (_reason, p, s, state) => {
  expect(parsePanelSpec({ ...group(["p", "s"], { p, s }), state })).toMatchObject({ ok: false });
});

it.each([
  ["unknown component", { type: "constructor", props: {} }],
  ["unknown prop", { type: "Section", props: { title: "Settings", className: "hidden" } }],
  [
    "mixed expression",
    { type: "Text", props: { content: { $state: "/data/title", fallback: "ignored" } } },
  ],
  ["missing data", { type: "Text", props: { content: { $state: "/data/unknown" } } }],
  ["wrong bound text type", { type: "Text", props: { content: { $state: "/data/workers" } } }],
  [
    "wrong bound table type",
    { type: "Table", props: { ...table, rows: { $state: "/panel/title" } } },
  ],
  ["ambient state", { type: "Text", props: { content: { $state: "/module/actions" } } }],
  ["pointer traversal", { type: "Text", props: { content: { $state: "/data/workers/0/id" } } }],
  ["prototype read", { type: "Text", props: { content: { $state: "/data/toString" } } }],
  ["unregistered directive", { type: "Badge", props: { text: { $newDirective: "text" } } }],
  [
    "binding to rendered cells",
    { type: "Table", props: { ...table, rows: [{ id: { $state: "/data/title" } }] } },
  ],
  [
    "extra column property",
    { type: "Table", props: { ...table, columns: [{ key: "id", label: "ID", href: "/" }] } },
  ],
  [
    "duplicate column key",
    { type: "Table", props: { ...table, columns: [...table.columns, ...table.columns] } },
  ],
  ["nonprimitive table cell", { type: "Table", props: { ...table, rows: [{ id: [1] }] } }],
  ["bound action list", { type: "Actions", props: { ids: { $state: "/data/workers" } } }],
  [
    "action overrides",
    { type: "Actions", props: { ids: ["deploy"], label: "No confirmation", args: {} } },
  ],
  ...["visible", "repeat", "on", "watch", "slots"].map((name): [string, unknown] => [
    name,
    { ...text, [name]: {} },
  ]),
])("rejects %s even when another branch declares valid actions", (_reason, invalid) => {
  expect(
    parsePanelSpec({
      ...group(["controls", "bad"], { controls: actions, bad: invalid }),
      state: { data },
    }),
  ).toMatchObject({ ok: false, error: expect.any(String) });
});

it.each([
  ["unknown envelope field", { ...group([], {}), onLoad: "run" }],
  [
    "author-supplied module scope",
    { ...group([], {}), state: { data, module: { id: "foreign" } } },
  ],
  [
    "unsafe unused data",
    { ...group([], {}), state: { data: JSON.parse('{"__proto__":"unused"}') } },
  ],
  ["missing root", { root: "elsewhere", elements: { a: actions } }],
  ["missing child", group(["missing"], {})],
  ["unreachable controls", group([], { extra: actions })],
  ["self-reference", group(["root"], {})],
  [
    "shared child",
    group(["a", "branch"], { a: actions, branch: { type: "Stack", props: {}, children: ["a"] } }),
  ],
  ["leaf with children", group(["a"], { a: { ...text, children: ["b"] }, b: actions })],
])("rejects the whole document for %s", (_reason, doc) => {
  expect(parsePanelSpec(doc)).toMatchObject({ ok: false, error: expect.any(String) });
});

it("bounds both input and rendered size, including repeated uses of one public dataset", () => {
  const dataTable = {
    type: "Table",
    props: { columns: table.columns, rows: { $state: "/data/workers" } },
  };
  const keys = Array.from({ length: 32 }, (_, i) => `t${i}`);
  const doc = group(keys, Object.fromEntries(keys.map((key) => [key, dataTable])));
  expect(
    parsePanelSpec({
      ...doc,
      state: { data: { workers: Array.from({ length: 128 }, () => ({ id: 0 })) } },
    }),
  ).toMatchObject({ ok: false, error: expect.stringMatching(/table cells/) });
  const deep = Object.fromEntries(
    keys.map((key, i) => [key, { type: "Stack", props: {}, children: keys.slice(i + 1, i + 2) }]),
  );
  expect(parsePanelSpec({ root: keys[0], elements: deep })).toMatchObject({
    ok: false,
    error: expect.stringMatching(/levels/),
  });
  expect(
    parsePanelSpec({ ...group([], {}), state: { data: { title: "x".repeat(140_000) } } }),
  ).toMatchObject({ ok: false, error: expect.stringMatching(/budget/) });
});
