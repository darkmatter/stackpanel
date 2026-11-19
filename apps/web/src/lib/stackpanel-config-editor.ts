export interface StackpanelOptionDoc {
  type?: string;
  description?: string;
  default?: {
    _type?: string;
    text?: string;
  };
  example?: {
    _type?: string;
    text?: string;
  };
}

export type JsonSchema = {
  [key: string]: unknown;
};

export type ConfigFileTarget = "config" | "local";

export interface ConfigFileProjection {
  exists?: boolean;
  config?: unknown;
  isFunction?: boolean;
}

interface SchemaNode {
  option?: StackpanelOptionDoc;
  properties: Record<string, SchemaNode>;
  wildcard: SchemaNode | null;
}

// Keep plain non-flake config functions independent of flake resolution. The
// public SDK thunk is forced only if the function actually uses lib.stackpanel.
const configModuleLib = `pkgs.lib // { stackpanel =
    let project = builtins.getFlake (toString ./.);
    in (project.inputs.stackpanel or project).lib; }`;

export const CONFIG_FILE_PATHS: Record<ConfigFileTarget, string> = {
  config: ".stack/config.nix",
  local: ".stack/config.local.nix",
};

function configFileProjection(target: ConfigFileTarget): string {
  return `
let
  pkgs = import <nixpkgs> {};
  lib = ${configModuleLib};
  file = ./${CONFIG_FILE_PATHS[target]};
  exists = builtins.pathExists file;
  raw = ${target === "local" ? "if exists then import file else {}" : "import file"};
  isFunction = builtins.isFunction raw;
  result = if isFunction then raw {
    inherit pkgs lib;
    inputs = {};
    self = ./.;
    config = result;
  } else raw;
in {
  inherit exists isFunction;
  config = result;
}
`;
}

export const CONFIG_FILE_PROJECTION_EVALS: Record<ConfigFileTarget, string> = {
  config: configFileProjection("config"),
  local: configFileProjection("local"),
};

export const STACKPANEL_OPTIONS_DOC_EVAL = `
let
  project = builtins.getFlake (toString ./.);
  stackpanel = project.inputs.stackpanel or project;
  pkgs = project.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
  mkOptionsDoc = import (stackpanel + "/nix/stackpanel/lib/options-doc.nix") { inherit pkgs; inherit (pkgs) lib; };
  optionsDoc = mkOptionsDoc { options = project.legacyPackages.\${builtins.currentSystem}.stackpanelOptions; };
in builtins.fromJSON (builtins.readFile (optionsDoc.optionsJSON + "/share/doc/nixos/options.json"))
`;

export function buildLocalConfigJsonSchema(
  optionsDoc: Record<string, StackpanelOptionDoc>,
): JsonSchema {
  const root = createSchemaNode();

  for (const [path, option] of Object.entries(optionsDoc)) {
    if (!path.startsWith("stackpanel.")) {
      continue;
    }

    const trimmedPath = path.replace(/^stackpanel\./, "");
    if (!trimmedPath) {
      continue;
    }

    const segments = trimmedPath.split(".");
    let current = root;

    for (const segment of segments) {
      if (isWildcardSegment(segment)) {
        current.wildcard ??= createSchemaNode();
        current = current.wildcard;
        continue;
      }

      current.properties[segment] ??= createSchemaNode();
      current = current.properties[segment];
    }

    current.option = option;
  }

  return {
    $schema: "http://json-schema.org/draft-07/schema#",
    title: "Stackpanel Local Config",
    description: "JSON projection of config.local.nix. Save writes the edited attrset back to Nix.",
    ...schemaNodeToJsonSchema(root, true),
  };
}

export function renderNixAttrset(value: unknown): string {
  if (!isRecord(value)) {
    throw new Error("Config must be a JSON object at the root");
  }

  return `${renderNixValue(value, 0)}\n`;
}

export function renderNixFile(
  value: unknown,
  options: {
    existingSource?: string;
    defaultFunctionHeader?: string | null;
  } = {},
): string {
  const attrsetExpr = renderNixAttrset(value).trimEnd();
  const existingSource = options.existingSource ?? "";

  if (!existingSource.trim()) {
    if (options.defaultFunctionHeader) {
      return `${options.defaultFunctionHeader}\n${attrsetExpr}\n`;
    }
    return `${attrsetExpr}\n`;
  }

  const functionWrapperMatch = existingSource.match(
    /^(?<prefix>[\s\S]*?\}:\s*)(?<body>\{[\s\S]*\})\s*$/,
  );
  if (functionWrapperMatch?.groups?.prefix) {
    return `${functionWrapperMatch.groups.prefix}${attrsetExpr}\n`;
  }

  const attrsetMatch = existingSource.match(/^(?<prefix>[\s\S]*?)(?<body>\{[\s\S]*\})\s*$/);
  if (attrsetMatch?.groups?.prefix !== undefined) {
    return `${attrsetMatch.groups.prefix}${attrsetExpr}\n`;
  }

  if (options.defaultFunctionHeader) {
    return `${options.defaultFunctionHeader}\n${attrsetExpr}\n`;
  }

  return `${attrsetExpr}\n`;
}

function createSchemaNode(): SchemaNode {
  return {
    properties: {},
    wildcard: null,
  };
}

function isWildcardSegment(segment: string): boolean {
  return /^<.+>$/.test(segment);
}

function schemaNodeToJsonSchema(node: SchemaNode, isRoot = false): JsonSchema {
  const baseSchema = optionTypeToJsonSchema(node.option?.type);
  const schema: JsonSchema = { ...baseSchema };

  const propertyEntries = Object.entries(node.properties);
  if (propertyEntries.length > 0 || node.wildcard || isRoot) {
    schema.type = schema.type ?? "object";
  }

  if (propertyEntries.length > 0) {
    schema.properties = Object.fromEntries(
      propertyEntries.map(([key, child]) => [key, schemaNodeToJsonSchema(child)]),
    );
  }

  if (node.wildcard) {
    schema.additionalProperties = schemaNodeToJsonSchema(node.wildcard);
  } else if (isRoot) {
    schema.additionalProperties = false;
  }

  const description = buildDescription(node.option);
  if (description) {
    schema.description = description;
    schema.markdownDescription = description;
  }

  return schema;
}

function buildDescription(option?: StackpanelOptionDoc): string | null {
  if (!option) {
    return null;
  }

  const parts = [option.description?.trim(), option.example?.text?.trim()].filter(
    (value): value is string => Boolean(value),
  );

  if (parts.length === 0) {
    return null;
  }

  if (parts.length === 1) {
    return parts[0];
  }

  return `${parts[0]}\n\nExample:\n${parts[1]}`;
}

function optionTypeToJsonSchema(type?: string): JsonSchema {
  const normalized = normalizeType(type);
  if (!normalized) {
    return {};
  }

  if (normalized.startsWith("null or ")) {
    return makeNullable(
      optionTypeToJsonSchema(stripOuterParens(normalized.slice("null or ".length))),
    );
  }

  if (normalized.startsWith("one of ")) {
    const enumValues = extractEnumValues(normalized);
    return {
      type: "string",
      enum: enumValues,
    };
  }

  if (normalized.startsWith("list of ")) {
    return {
      type: "array",
      items: optionTypeToJsonSchema(stripOuterParens(normalized.slice("list of ".length))),
    };
  }

  if (normalized.startsWith("attribute set of ")) {
    return {
      type: "object",
      additionalProperties: optionTypeToJsonSchema(
        stripOuterParens(normalized.slice("attribute set of ".length)),
      ),
    };
  }

  if (normalized.includes("submodule") || normalized === "attribute set") {
    return { type: "object" };
  }

  if (normalized === "boolean") {
    return { type: "boolean" };
  }

  if (normalized.includes("integer")) {
    return { type: "integer" };
  }

  if (
    normalized === "string" ||
    normalized.includes("path") ||
    normalized.includes("package") ||
    normalized.includes("module") ||
    normalized.includes("strings concatenated")
  ) {
    return { type: "string" };
  }

  if (normalized.includes("anything") || normalized.includes("unspecified value")) {
    return {};
  }

  return {};
}

function normalizeType(type?: string): string {
  return type?.replace(/\s+/g, " ").trim().toLowerCase() ?? "";
}

function stripOuterParens(value: string): string {
  if (value.startsWith("(") && value.endsWith(")")) {
    return value.slice(1, -1).trim();
  }

  return value;
}

function extractEnumValues(type: string): Array<string | null> {
  const values = [...type.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  return values;
}

function makeNullable(schema: JsonSchema): JsonSchema {
  const nextSchema = { ...schema };
  const currentType = nextSchema.type;

  if (Array.isArray(currentType)) {
    nextSchema.type = currentType.includes("null") ? currentType : [...currentType, "null"];
    return nextSchema;
  }

  if (typeof currentType === "string") {
    nextSchema.type = [currentType, "null"];
    if (Array.isArray(nextSchema.enum) && !nextSchema.enum.includes(null)) {
      nextSchema.enum = [...nextSchema.enum, null];
    }
    return nextSchema;
  }

  return {
    anyOf: [schema, { type: "null" }],
  };
}

function renderNixValue(value: unknown, depth: number): string {
  const indent = "  ".repeat(depth);
  const nextIndent = "  ".repeat(depth + 1);

  if (value === null) {
    return "null";
  }

  if (typeof value === "string") {
    return quoteNixString(value);
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new Error("Only finite numbers can be written to Nix config files");
    }
    return String(value);
  }

  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }

  if (Array.isArray(value)) {
    if (value.length === 0) {
      return "[ ]";
    }

    const items = value.map((item) => `${nextIndent}${renderNixValue(item, depth + 1)}`).join("\n");
    return `[\n${items}\n${indent}]`;
  }

  if (isRecord(value)) {
    const entries = Object.entries(value);
    if (entries.length === 0) {
      return "{ }";
    }

    const lines = entries
      .map(
        ([key, nestedValue]) =>
          `${nextIndent}${renderNixKey(key)} = ${renderNixValue(nestedValue, depth + 1)};`,
      )
      .join("\n");

    return `{\n${lines}\n${indent}}`;
  }

  throw new Error(`Unsupported value in local config: ${String(value)}`);
}

function renderNixKey(key: string): string {
  if (/^[A-Za-z_][A-Za-z0-9_'-]*$/.test(key)) {
    return key;
  }

  return quoteNixString(key);
}

function quoteNixString(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\$\{/g, "\\${")}"`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
