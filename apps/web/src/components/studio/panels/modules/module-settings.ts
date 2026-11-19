import type { JsonObject, JsonValue } from "@bufbuild/protobuf";
import { fromJSONSchema, registry, type ZodType } from "zod";

export function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export interface SettingsSchema {
  definition: JsonObject;
  fields: { name: string; schema: JsonObject; readOnly: boolean }[];
  validator: ZodType;
}

export function readSettingsSchema(
  raw: string | JsonObject | null | undefined,
): SettingsSchema | null {
  if (!raw) return null;
  const definition: unknown = typeof raw === "string" ? JSON.parse(raw) : raw;
  if (!isObject(definition)) throw new Error("Expected a JSON Schema object.");
  const { properties } = definition;
  if (properties !== undefined && !isObject(properties)) {
    throw new Error("Schema properties must be an object.");
  }
  const fields = Object.entries(properties ?? {}).map(([name, field]) => {
    if (typeof field !== "boolean" && !isObject(field))
      throw new Error(`Invalid schema for ${name}.`);
    return {
      name,
      schema: isObject(field) ? field : {},
      readOnly: field === false || (isObject(field) && field.readOnly === true),
    };
  });
  return { definition, fields, validator: fromJSONSchema(definition, { registry: registry() }) };
}

export function parseSettings(text: string): JsonObject {
  const value: unknown = JSON.parse(text);
  if (!isObject(value)) throw new Error("Settings must be a JSON object.");
  return value;
}

export function fieldKind(field: JsonObject) {
  if (Array.isArray(field.enum) && field.enum.length > 0) return "enum";
  switch (field.type) {
    case "string":
      return "string";
    case "integer":
    case "number":
      return "number";
    case "boolean":
      return "boolean";
    default:
      return "json";
  }
}

export function formatField(field: JsonObject, value: JsonValue | undefined) {
  if (value === undefined) return "";
  return fieldKind(field) === "string" && typeof value === "string"
    ? value
    : JSON.stringify(value, null, 2);
}

export function applyFieldEdits(
  settings: JsonObject,
  edits: Record<string, string>,
  schema: SettingsSchema | null,
) {
  const next = { ...settings };
  for (const { name, schema: field } of schema?.fields ?? []) {
    if (!Object.hasOwn(edits, name)) continue;
    const text = edits[name]!;
    try {
      const value: JsonValue = fieldKind(field) === "string" ? text : JSON.parse(text);
      Object.defineProperty(next, name, {
        value,
        enumerable: true,
        configurable: true,
        writable: true,
      });
    } catch {
      throw new Error(
        `${name}: expected ${field.type === "number" || field.type === "integer" ? "a number" : "valid JSON"}.`,
      );
    }
  }
  return next;
}

// The agent merges each object leaf. Omitted attributes and new empty
// objects can't be expressed as edits; don't report them as a successful save.
function changedLeaves(before: JsonObject, after: JsonObject, path: string[] = []): JsonObject {
  const changes: [string, JsonValue][] = [];
  for (const key of Object.keys(before)) {
    if (!Object.hasOwn(after, key))
      throw new Error(
        `Removing ${[...path, key].join(" → ")} isn't supported by a settings patch.`,
      );
  }
  for (const [key, value] of Object.entries(after)) {
    const old = Object.hasOwn(before, key) ? before[key] : undefined;
    if (isObject(value)) {
      if (!isObject(old) && !Object.keys(value).length) {
        throw new Error(
          `Can't set ${[...path, key].join(" → ")} to an empty object with a settings patch.`,
        );
      }
      const patch = changedLeaves(isObject(old) ? old : {}, value, [...path, key]);
      if (Object.keys(patch).length) changes.push([key, patch]);
    } else if (JSON.stringify(old) !== JSON.stringify(value)) {
      changes.push([key, value]);
    }
  }
  return Object.fromEntries(changes);
}

export function settingsPatch(
  saved: JsonObject,
  next: JsonObject,
  schema: SettingsSchema | null,
): JsonObject {
  const patch = changedLeaves(saved, next);
  for (const field of schema?.fields ?? []) {
    if (field.readOnly && Object.hasOwn(patch, field.name))
      throw new Error(`${field.name} is read-only.`);
  }
  const validation = schema?.validator.safeParse(next);
  if (validation && !validation.success) {
    throw new Error(
      validation.error.issues
        .map((issue) => `${issue.path.join(" → ") || "Settings"}: ${issue.message}`)
        .join("\n"),
    );
  }
  return patch;
}
