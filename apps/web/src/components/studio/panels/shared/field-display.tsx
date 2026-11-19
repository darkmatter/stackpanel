"use client";

/**
 * Read-only field display renderer.
 *
 * Renders panel fields as formatted, non-editable values: badges for
 * booleans and arrays, pre-blocks for objects and code, plain text for
 * strings.
 */

import { Badge } from "@ui/badge";
import { useMemo } from "react";
import { useNixConfigQuery } from "@/lib/use-agent";
import { ModuleMarkdown } from "./module-markdown";
import type { NixPanelField } from "./panel-types";

export interface FieldDisplayProps {
  field: NixPanelField;
}

function record(value: unknown): Record<string, unknown> | undefined {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
}

/** Workspace secrets are variable IDs, not backend settings or master keys. */
export function SecretReference({
  value,
  id,
  label,
  disabled,
  onChange,
}: {
  value: string;
  label: string;
  id?: string;
  disabled?: boolean;
  onChange?: (key: string) => void;
}) {
  const { data, isLoading, isError } = useNixConfigQuery();
  const config = data?.config;
  const keys = useMemo(() => {
    const extra = record(config?.serializable);
    const secretManifest = record(extra?.secrets);
    // The wire projection merges backend settings into variables. They are
    // repeated in serializable.variables and are not IDs a module can bind.
    const backendSettings = record(extra?.variables) ?? {};
    return new Set(
      [
        ...Object.keys(record(config?.variables) ?? {}).filter(
          (key) => !Object.hasOwn(backendSettings, key),
        ),
        ...Object.keys(record(secretManifest?.variables) ?? {}),
        ...Object.keys(record(record(config?.secrets)?.variables) ?? {}),
      ].sort(),
    );
  }, [config]);

  const known = keys.has(value);
  if (!onChange) {
    return (
      <span className="text-sm font-mono">
        {known ? value : value ? "Reference unavailable" : "Not set"}
      </span>
    );
  }

  let prompt = "Select a variable or secret";
  if (isLoading) prompt = "Loading references…";
  else if (isError) prompt = "Could not load references";
  else if (!keys.size) prompt = "No references available";
  else if (value && !known) prompt = "Reference unavailable — choose a key";

  return (
    <select
      id={id}
      aria-label={label}
      className="h-8 w-full rounded-md border bg-background px-2 text-xs"
      disabled={disabled || isError || !keys.size}
      value={known ? value : ""}
      onChange={(event) => {
        const key = event.currentTarget.value;
        if (keys.has(key)) onChange(key);
      }}
    >
      <option value="" disabled>
        {prompt}
      </option>
      {Array.from(keys, (key) => (
        <option key={key} value={key}>
          {key}
        </option>
      ))}
    </select>
  );
}

export function selectedFieldItems(value: string): string[] {
  try {
    const parsed: unknown = JSON.parse(value);
    if (Array.isArray(parsed))
      return [...new Set(parsed.filter((item): item is string => typeof item === "string"))];
    return typeof parsed === "string" ? [parsed] : [];
  } catch {
    return value ? [value] : [];
  }
}

export function FieldDisplay({ field }: FieldDisplayProps) {
  if (field.type === "FIELD_TYPE_MARKDOWN" || field.type === "FIELD_TYPE_SECRET_REF") {
    const label = field.label ?? field.name;
    return (
      <div className="space-y-1">
        <div className="text-xs text-muted-foreground font-medium">{label}</div>
        {field.type === "FIELD_TYPE_MARKDOWN" ? (
          <ModuleMarkdown>{field.value ?? ""}</ModuleMarkdown>
        ) : (
          <SecretReference value={field.value ?? ""} label={label} />
        )}
      </div>
    );
  }

  if (field.type === "FIELD_TYPE_MULTISELECT") {
    const items = selectedFieldItems(field.value ?? "");
    const labels = new Map(
      field.options?.map((opt) =>
        typeof opt === "string" ? ([opt, opt] as const) : ([opt.value, opt.label] as const),
      ),
    );
    return (
      <div className="space-y-1">
        <div className="text-xs text-muted-foreground font-medium">{field.label ?? field.name}</div>
        <div className="flex flex-wrap gap-1">
          {items.length
            ? items.map((key) => (
                <Badge key={key} variant="secondary">
                  {labels.get(key) ?? key}
                </Badge>
              ))
            : "None"}
        </div>
      </div>
    );
  }

  // Try to parse JSON values for better display
  if (field.type === "FIELD_TYPE_JSON" || field.type === "FIELD_TYPE_STRING") {
    try {
      const parsed = JSON.parse(field.value ?? "");

      // Array: render as badge list
      if (Array.isArray(parsed)) {
        return (
          <div className="space-y-1">
            <div className="text-xs text-muted-foreground font-medium">
              {field.label ?? field.name}
            </div>
            <div className="flex flex-wrap gap-1">
              {parsed.map((item, i) => {
                const label =
                  typeof item === "string"
                    ? item
                    : (item.name ?? item.label ?? JSON.stringify(item));
                return (
                  <Badge key={`${label}-${i}`} variant="secondary" className="text-xs">
                    {label}
                  </Badge>
                );
              })}
            </div>
          </div>
        );
      }

      // Object: render as formatted JSON
      if (typeof parsed === "object" && parsed !== null) {
        return (
          <div className="space-y-1">
            <div className="text-xs text-muted-foreground font-medium">
              {field.label ?? field.name}
            </div>
            <div className="rounded-md border bg-muted/30 p-2">
              <pre className="text-xs font-mono whitespace-pre-wrap">
                {JSON.stringify(parsed, null, 2)}
              </pre>
            </div>
          </div>
        );
      }
    } catch {
      // Not JSON, render as string below
    }
  }

  if (field.type === "FIELD_TYPE_CODE") {
    return (
      <div className="space-y-1">
        <div className="text-xs text-muted-foreground font-medium">{field.label ?? field.name}</div>
        <div className="rounded-md border bg-muted/50 p-3">
          <pre className="text-xs font-mono whitespace-pre-wrap leading-relaxed">
            {field.value || "# No code"}
          </pre>
        </div>
      </div>
    );
  }

  if (field.type === "FIELD_TYPE_BOOLEAN") {
    return (
      <div className="flex items-center gap-2">
        <div className="text-xs text-muted-foreground font-medium">{field.label ?? field.name}</div>
        <Badge variant={field.value === "true" ? "default" : "secondary"}>
          {field.value === "true" ? "Enabled" : "Disabled"}
        </Badge>
      </div>
    );
  }

  // Default: plain text
  return (
    <div className="space-y-0.5">
      <div className="text-xs text-muted-foreground font-medium">{field.label ?? field.name}</div>
      <div className="text-sm font-mono">{field.value || "-"}</div>
    </div>
  );
}
