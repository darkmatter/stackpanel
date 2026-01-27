"use client";

/**
 * Editable field renderer for panel config fields.
 *
 * Supports STRING, BOOLEAN, SELECT, MULTISELECT, JSON, NUMBER, and CODE
 * field types. Commits changes on blur (text inputs) or immediately (toggles,
 * selects). Used by AppConfigFormRenderer and the Panels screen.
 */

import { Badge } from "@ui/badge";
import { Input } from "@ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import type { AppConfigField } from "./panel-types";

export interface FieldRendererProps {
  field: AppConfigField;
  value: string;
  disabled?: boolean;
  isSaving?: boolean;
  onChange: (value: string) => void;
}

export function FieldRenderer({
  field,
  value,
  disabled,
  isSaving,
  onChange,
}: FieldRendererProps) {
  switch (field.type) {
    case "FIELD_TYPE_BOOLEAN":
      return (
        <div className="flex items-center gap-2">
          <Switch
            checked={value === "true"}
            disabled={disabled || isSaving}
            onCheckedChange={(checked) => onChange(String(checked))}
          />
          <span className="text-xs text-muted-foreground">
            {value === "true" ? "Enabled" : "Disabled"}
          </span>
        </div>
      );

    case "FIELD_TYPE_SELECT":
      return (
        <Select
          value={value}
          disabled={disabled || isSaving}
          onValueChange={onChange}
        >
          <SelectTrigger size="sm" className="w-full">
            <SelectValue placeholder={field.placeholder ?? "Select..."} />
          </SelectTrigger>
          <SelectContent>
            {(field.options ?? []).map((opt) => (
              <SelectItem key={opt} value={opt}>
                {opt}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      );

    case "FIELD_TYPE_MULTISELECT": {
      let items: string[] = [];
      try {
        items = JSON.parse(value);
      } catch {
        items = value ? [value] : [];
      }

      return (
        <div className="space-y-1">
          <div className="flex flex-wrap gap-1">
            {items.map((item, i) => (
              <Badge
                key={`${item}-${i}`}
                variant="secondary"
                className="text-[10px] gap-1"
              >
                {item}
                {!disabled && (
                  <button
                    type="button"
                    className="ml-0.5 hover:text-destructive"
                    onClick={() => {
                      const next = items.filter((_, idx) => idx !== i);
                      onChange(JSON.stringify(next));
                    }}
                  >
                    x
                  </button>
                )}
              </Badge>
            ))}
          </div>
          {!disabled && (
            <Input
              placeholder={field.placeholder ?? "Add item..."}
              className="h-7 text-xs"
              disabled={isSaving}
              onKeyDown={(e) => {
                if (e.key === "Enter" && e.currentTarget.value.trim()) {
                  const next = [...items, e.currentTarget.value.trim()];
                  onChange(JSON.stringify(next));
                  e.currentTarget.value = "";
                }
              }}
            />
          )}
        </div>
      );
    }

    case "FIELD_TYPE_JSON":
      return (
        <Input
          value={value}
          placeholder={field.placeholder ?? "JSON..."}
          className="h-7 text-xs font-mono"
          disabled={disabled || isSaving}
          onBlur={(e) => {
            if (e.target.value !== value) {
              onChange(e.target.value);
            }
          }}
        />
      );

    case "FIELD_TYPE_NUMBER":
      return (
        <Input
          type="number"
          value={value}
          placeholder={field.placeholder}
          className="h-7 text-xs"
          disabled={disabled || isSaving}
          onBlur={(e) => {
            if (e.target.value !== value) {
              onChange(e.target.value);
            }
          }}
        />
      );

    case "FIELD_TYPE_CODE":
      return (
        <textarea
          value={value}
          placeholder={field.placeholder ?? "# Nix expression..."}
          rows={5}
          className="w-full rounded-md border border-border bg-muted/50 px-3 py-2 text-xs font-mono leading-relaxed resize-y focus:outline-none focus:ring-1 focus:ring-ring disabled:opacity-50"
          disabled={disabled || isSaving}
          spellCheck={false}
          onBlur={(e) => {
            if (e.target.value !== value) {
              onChange(e.target.value);
            }
          }}
        />
      );

    case "FIELD_TYPE_STRING":
    default:
      return (
        <Input
          value={value}
          placeholder={field.placeholder}
          className="h-7 text-xs"
          disabled={disabled || isSaving}
          onBlur={(e) => {
            if (e.target.value !== value) {
              onChange(e.target.value);
            }
          }}
        />
      );
  }
}
