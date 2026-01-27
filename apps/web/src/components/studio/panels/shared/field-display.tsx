"use client";

/**
 * Read-only field display renderer.
 *
 * Renders panel fields as formatted, non-editable values: badges for
 * booleans and arrays, pre-blocks for objects and code, plain text for
 * strings.
 */

import { Badge } from "@ui/badge";
import type { NixPanelField } from "./panel-types";

export interface FieldDisplayProps {
  field: NixPanelField;
}

export function FieldDisplay({ field }: FieldDisplayProps) {
  // Try to parse JSON values for better display
  if (field.type === "FIELD_TYPE_JSON" || field.type === "FIELD_TYPE_STRING") {
    try {
      const parsed = JSON.parse(field.value);

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
                    : item.name ?? item.label ?? JSON.stringify(item);
                return (
                  <Badge
                    key={`${label}-${i}`}
                    variant="secondary"
                    className="text-xs"
                  >
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
        <div className="text-xs text-muted-foreground font-medium">
          {field.label ?? field.name}
        </div>
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
        <div className="text-xs text-muted-foreground font-medium">
          {field.label ?? field.name}
        </div>
        <Badge variant={field.value === "true" ? "default" : "secondary"}>
          {field.value === "true" ? "Enabled" : "Disabled"}
        </Badge>
      </div>
    );
  }

  // Default: plain text
  return (
    <div className="space-y-0.5">
      <div className="text-xs text-muted-foreground font-medium">
        {field.label ?? field.name}
      </div>
      <div className="text-sm font-mono">{field.value || "-"}</div>
    </div>
  );
}
