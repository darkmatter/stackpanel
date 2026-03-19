const fs = require("node:fs");

function main() {
  const inputPath = process.argv[2];

  if (!inputPath) {
    throw new Error("usage: node options-doc-to-schema.js <options.json>");
  }

  const optionsDoc = JSON.parse(fs.readFileSync(inputPath, "utf8"));
  const schema = buildLocalConfigJsonSchema(optionsDoc);

  process.stdout.write(`${JSON.stringify(schema, null, 2)}\n`);
}

function buildLocalConfigJsonSchema(optionsDoc) {
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
    title: "Stackpanel Config",
    description: "JSON projection of .stack/config.nix or config.local.nix.",
    ...schemaNodeToJsonSchema(root, true),
  };
}

function createSchemaNode() {
  return {
    option: null,
    properties: {},
    wildcard: null,
  };
}

function isWildcardSegment(segment) {
  return /^<.+>$/.test(segment);
}

function schemaNodeToJsonSchema(node, isRoot = false) {
  const baseSchema = optionTypeToJsonSchema(node.option && node.option.type);
  const schema = { ...baseSchema };

  const propertyEntries = Object.entries(node.properties);
  if (propertyEntries.length > 0 || node.wildcard || isRoot) {
    schema.type = schema.type || "object";
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

function buildDescription(option) {
  if (!option) {
    return null;
  }

  const parts = [
    typeof option.description === "string" ? option.description.trim() : null,
    option.example && typeof option.example.text === "string"
      ? option.example.text.trim()
      : null,
  ].filter(Boolean);

  if (parts.length === 0) {
    return null;
  }

  if (parts.length === 1) {
    return parts[0];
  }

  return `${parts[0]}\n\nExample:\n${parts[1]}`;
}

function optionTypeToJsonSchema(type) {
  const normalized = normalizeType(type);
  if (!normalized) {
    return {};
  }

  if (normalized.startsWith("null or ")) {
    return makeNullable(optionTypeToJsonSchema(stripOuterParens(normalized.slice("null or ".length))));
  }

  if (normalized.startsWith("one of ")) {
    return {
      type: "string",
      enum: extractEnumValues(normalized),
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

function normalizeType(type) {
  return typeof type === "string" ? type.replace(/\s+/g, " ").trim().toLowerCase() : "";
}

function stripOuterParens(value) {
  if (value.startsWith("(") && value.endsWith(")")) {
    return value.slice(1, -1).trim();
  }

  return value;
}

function extractEnumValues(type) {
  return [...type.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

function makeNullable(schema) {
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

main();
