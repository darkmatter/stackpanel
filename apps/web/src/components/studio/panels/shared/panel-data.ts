import type { JsonObject, JsonValue } from "@bufbuild/protobuf";
import type { MetricItem, NixPanelColumn } from "./panel-types";

export function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The evaluated descriptor must describe the action an operator is being asked to run. */
export function hasActionReview(value: unknown): value is JsonObject & {
  label: string;
  argsSchema: JsonObject;
  outputMode: "json" | "stream";
} {
  return (
    isJsonObject(value) &&
    typeof value.label === "string" &&
    value.label.trim().length > 0 &&
    isJsonObject(value.argsSchema) &&
    value.argsSchema.type === "object" &&
    (value.outputMode === "json" || value.outputMode === "stream")
  );
}

export function displayCell(value: JsonValue | undefined) {
  if (value == null) return "—";
  return typeof value === "object" ? JSON.stringify(value) : String(value);
}

/** Providers can return rows directly, or { rows, columns? }. Declared columns win. */
export function tableData(json: JsonValue | undefined, declaredColumns: NixPanelColumn[]) {
  const rows = isJsonObject(json) ? json.rows : json;
  if (!Array.isArray(rows) || !rows.every(isJsonObject))
    throw new Error("Expected a JSON array of row objects or an object with a rows array.");
  let columns = declaredColumns;
  if (!columns.length && isJsonObject(json) && json.columns !== undefined) {
    if (!Array.isArray(json.columns)) throw new Error("Expected a columns array.");
    columns = json.columns.map((column) => {
      if (
        !isJsonObject(column) ||
        typeof column.key !== "string" ||
        typeof column.label !== "string"
      )
        throw new Error("Each column must have a key and label.");
      return { key: column.key, label: column.label };
    });
  }
  if (!columns.length)
    columns = Array.from(new Set(rows.flatMap(Object.keys)), (key) => ({ key, label: key }));
  return { rows, columns };
}

/** Status providers return metric objects, { metrics: [...] }, or a simple named status map. */
export function statusMetrics(json: JsonValue | undefined): MetricItem[] {
  const metrics = isJsonObject(json) && Object.hasOwn(json, "metrics") ? json.metrics : json;
  if (isJsonObject(metrics))
    return Object.entries(metrics).map(([label, value]) => ({ label, value: displayCell(value) }));
  if (!Array.isArray(metrics))
    throw new Error("Expected a JSON metrics array or a named status object.");
  return metrics.map((metric) => {
    if (
      !isJsonObject(metric) ||
      typeof metric.label !== "string" ||
      !Object.hasOwn(metric, "value")
    )
      throw new Error("Each metric must have a label and value.");
    const status = metric.status === "warning" ? "warn" : metric.status;
    return {
      label: metric.label,
      value: displayCell(metric.value),
      status: status === "ok" || status === "warn" || status === "error" ? status : undefined,
    };
  });
}
