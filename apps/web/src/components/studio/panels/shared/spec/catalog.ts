import { defineCatalog, type Spec } from "@json-render/core";
import { schema } from "@json-render/react/schema";
import { z } from "zod";
import { components, id, limits, panelState, safeKey } from "./author-schema";

const maxTableCells = 4096;
export const panelCatalog = defineCatalog(schema, { components, actions: {} });

const element = z.strictObject({
  type: z.enum(Object.keys(components) as (keyof typeof components)[]),
  props: z.record(id, z.unknown()),
  children: z.array(id).max(limits.maxElements).optional(),
});
const envelope = z.strictObject({
  root: id,
  elements: z.record(id, element),
  state: panelState.optional(),
});
const reference = z.strictObject({ $state: z.string() });
const localBinding = z.strictObject({ $bindState: z.string().startsWith("/local/") });
type Document = z.infer<typeof envelope>;
type Result = { ok: true; spec: Spec; actionIds: string[] | "all" } | { ok: false; error: string };

// Bound work *before* a recursive parser or upstream resolver sees the document. In
// particular, a record parser may silently skip __proto__ instead of rejecting it.
function checkJsonBudget(input: unknown) {
  let values = 0;
  let characters = 0;
  function visit(value: unknown, depth: number) {
    if (++values > 8192 || depth > 12)
      throw new Error("Spec exceeds the JSON size or depth limit.");
    if (typeof value === "string") characters += value.length;
    if (characters > 131072) throw new Error("Spec exceeds the text budget.");
    if (
      value === null ||
      typeof value === "boolean" ||
      typeof value === "string" ||
      Number.isFinite(value)
    )
      return;
    if (typeof value !== "object") throw new Error("Use only finite JSON values.");
    const array = Array.isArray(value);
    const proto = Object.getPrototypeOf(value);
    if (array ? proto !== Array.prototype : proto !== null && proto !== Object.prototype) {
      throw new Error("Use only plain JSON objects and arrays.");
    }
    const keys = Reflect.ownKeys(value);
    if (keys.length > 128 + Number(array) || (array && value.length !== keys.length - 1)) {
      throw new Error("Use at most 128 entries per object or array and no sparse arrays.");
    }
    for (const key of keys) {
      if (array && key === "length") continue;
      if (
        typeof key !== "string" ||
        (key !== "$state" && key !== "$bindState" && !safeKey(key)) ||
        (array && (!/^(0|[1-9]\d*)$/.test(key) || Number(key) >= value.length))
      ) {
        throw new Error(`Unsupported JSON key: ${String(key).slice(0, 128)}.`);
      }
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor?.enumerable || !("value" in descriptor))
        throw new Error("Use plain JSON properties.");
      characters += key.length;
      visit(descriptor.value, depth + 1);
    }
  }
  visit(input, 0);
}

function parseAt<T>(validator: z.ZodType<T>, input: unknown, location: string): T {
  const result = validator.safeParse(input, { jitless: true });
  if (result.success) return result.data;
  const issue = result.error.issues[0]!;
  throw new Error(`${[location, ...issue.path].join(".")}: ${issue.message}`);
}

function checkTree({ root, elements }: Document) {
  const count = Object.keys(elements).length;
  if (count > limits.maxElements) throw new Error(`Use at most ${limits.maxElements} elements.`);
  const seen = new Set<string>();
  function visit(key: string, depth: number) {
    const node = elements[key];
    if (!node) throw new Error(`Missing element: ${key}.`);
    if (seen.has(key))
      throw new Error(
        `Element ${key} is referenced twice; use a tree, not a cycle or shared child.`,
      );
    if (depth > limits.maxDepth)
      throw new Error(`Use at most ${limits.maxDepth} levels of elements.`);
    seen.add(key);
    if (node.children?.length && !components[node.type].slots.length) {
      throw new Error(`Element ${key}: ${node.type} cannot have children.`);
    }
    for (const child of node.children ?? []) visit(child, depth + 1);
  }
  visit(root, 1);
  if (seen.size !== count) throw new Error("Remove elements not reachable from root.");
}

function publicValue(path: string, state: Document["state"], location: string) {
  // All three host-supplied values are strings, including the empty app id outside an app.
  if (path === "/module/id" || path === "/panel/title" || path === "/app/id") return "";
  const [, source, key, ...extra] = path.split("/");
  const values = source === "local" ? state?.local : source === "data" ? state?.data : undefined;
  if (
    path.startsWith("/") &&
    key &&
    !extra.length &&
    safeKey(key) &&
    values &&
    Object.hasOwn(values, key)
  )
    return values[key];
  throw new Error(`${location}: unknown public state path ${path.slice(0, 128)}.`);
}

export function parsePanelSpec(value: unknown): Result {
  try {
    checkJsonBudget(value);
    const spec = parseAt(envelope, value, "spec");
    checkTree(spec);
    const ids = new Set<string>();
    let all = false;
    const pickerChoices = new Map<string, string[]>();
    const statusSelections = new Map<string, string>();
    let cells = 0;
    for (const [key, node] of Object.entries(spec.elements)) {
      const definition = components[node.type];
      const location = `elements.${key}.props`;
      const resolved = { ...node.props };
      const references: Record<string, z.infer<typeof reference> | z.infer<typeof localBinding>> =
        {};
      let pickerPath: string | undefined;
      for (const [name, raw] of Object.entries(node.props)) {
        const mode = definition.bindings[name];
        if (mode === "bindLocal") {
          const binding = parseAt(localBinding, raw, `${location}.${name}`);
          pickerPath = binding.$bindState;
          if (pickerChoices.has(pickerPath))
            throw new Error(`${location}.${name}: only one picker may write ${pickerPath}.`);
          references[name] = binding;
          resolved[name] = publicValue(pickerPath, spec.state, `${location}.${name}`);
          continue;
        }
        if (!raw || typeof raw !== "object" || !Object.hasOwn(raw, "$state")) continue;
        if (!mode) throw new Error(`${location}.${name} cannot be bound.`);
        const ref = parseAt(reference, raw, `${location}.${name}`);
        if (mode === "data" && !ref.$state.startsWith("/data/"))
          throw new Error(`${location}.${name} must read a public data list.`);
        if (mode === "local" && !ref.$state.startsWith("/local/"))
          throw new Error(`${location}.${name} must read a local selection.`);
        if (node.type === "StatusView" && name === "app") {
          statusSelections.set(key, ref.$state);
        }
        references[name] = ref;
        resolved[name] = publicValue(ref.$state, spec.state, `${location}.${name}`);
      }
      // Check resolved values against the registry's actual props before restoring bindings.
      const props = parseAt<z.infer<typeof definition.props>>(definition.props, resolved, location);
      node.props = { ...props, ...references };
      if ("rows" in props) {
        cells += props.columns.length * (1 + props.rows.length);
        if (cells > maxTableCells)
          throw new Error(`Use at most ${maxTableCells} rendered table cells per spec.`);
      }
      if (pickerPath && "apps" in props) {
        if (props.value !== "" && !props.apps.includes(props.value)) {
          throw new Error(`${location}.value must be empty or one of the offered apps.`);
        }
        pickerChoices.set(pickerPath, props.apps);
      }
      if ("action" in props) ids.add(props.action);
      if (node.type === "Actions") {
        if ("ids" in props && props.ids) for (const actionId of props.ids) ids.add(actionId);
        else all = true;
      }
    }
    for (const [key, path] of statusSelections) {
      const choices = pickerChoices.get(path);
      if (!choices) throw new Error(`StatusView.app needs an AppPicker for ${path}.`);
      spec.elements[key]!.props.allowedApps = choices;
    }
    return { ok: true, spec, actionIds: all ? "all" : [...ids] };
  } catch (cause) {
    return {
      ok: false,
      error: cause instanceof Error ? cause.message : "Expected a panel spec object.",
    };
  }
}
