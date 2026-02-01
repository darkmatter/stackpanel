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
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import type { AppConfigField, NixFieldOption } from "./panel-types";
import { Field, FieldContent, FieldDescription, FieldGroup, FieldLabel, FieldLegend, FieldSet, FieldTitle } from '@stackpanel/ui-web/field';
import { Checkbox } from '@/components/ui/checkbox';
import { Combobox, ComboboxChip, ComboboxChips, ComboboxChipsInput, ComboboxContent, ComboboxEmpty, ComboboxItem, ComboboxList, ComboboxValue, useComboboxAnchor } from '@/components/ui/combobox';
import React from 'react';

/** Helper to normalize field options to {value, label} format */
function normalizeOption(opt: NixFieldOption): { value: string; label: string } {
  if (typeof opt === "string") {
    return { value: opt, label: opt };
  }
  return opt;
}

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
        <FieldLabel htmlFor={field.name}>
          <Field orientation="horizontal">
            <FieldContent>
              <FieldTitle>{field.label || field.name || ""}</FieldTitle>
              <FieldDescription className="text-xs text-muted-foreground/70">
                <span className="text-muted-foreground">
                  {field.description || ""}
                </span>
                {field.example && (
                  <p className="font-mono mt-0.5">
                    Example: <span className="text-muted-foreground">{field.example}</span>
                  </p>
                )}
              </FieldDescription>
            </FieldContent>
            <Switch
              id={field.name}
              checked={value === "true"}
              disabled={disabled || isSaving}
              onCheckedChange={(checked) => onChange(String(checked))}
            />
          </Field>
        </FieldLabel>
      );

    case "FIELD_TYPE_SELECT": {
      const options = (field.options ?? []).map(normalizeOption);
      return (
         <Field className="w-full max-w-xs">
            <FieldLabel>{field.label}</FieldLabel>
            <Select>
              <SelectTrigger>
                <SelectValue placeholder={field.placeholder ?? "Select..."} />
              </SelectTrigger>
              <SelectContent>
                <SelectGroup>
                  {options.map((opt) => (
                    <SelectItem key={opt.value} value={opt.value}>
                      {opt.label}
                    </SelectItem>
                  ))}
                </SelectGroup>
              </SelectContent>
            </Select>
            <FieldDescription  className="text-xs">
              {field.description || ""}
            </FieldDescription>
          </Field>
      );
    }

    case "FIELD_TYPE_MULTISELECT": {
      const anchor = useComboboxAnchor();
      let items: string[] = [];
      try {
        items = JSON.parse(value);
      } catch {
        items = value ? [value] : [];
      }

      return (
      <FieldSet>
        <FieldLegend variant="label">
          {field.label}
        </FieldLegend>
        <FieldDescription>
          {field.description || ""}
        </FieldDescription>
        <FieldGroup>
          <Combobox
      multiple
      autoHighlight
      items={items}
      defaultValue={[items[0]]}
    >
      <ComboboxChips ref={anchor} className="w-full max-w-xs">
        <ComboboxValue>
          {(values) => (
            <React.Fragment>
              {values.map((value: string) => (
                <ComboboxChip key={value}>{value}</ComboboxChip>
              ))}
              <ComboboxChipsInput />
            </React.Fragment>
          )}
        </ComboboxValue>
      </ComboboxChips>
      <ComboboxContent anchor={anchor}>
        <ComboboxEmpty>No items found.</ComboboxEmpty>
        <ComboboxList>
          {(item) => (
            <ComboboxItem key={item} value={item}>
              {item}
            </ComboboxItem>
          )}
        </ComboboxList>
      </ComboboxContent>
    </Combobox>
        </FieldGroup>
      </FieldSet>
      );
    }

    case "FIELD_TYPE_JSON":
      return (
        <Field>
          <FieldLabel htmlFor={field.name}>
            {field.label || field.name || ""}
          </FieldLabel>
          <Input
            value={value}
            placeholder={field.placeholder ?? "JSON..."}
            className="h-7 text-xs font-mono max-w-sm"
            disabled={disabled || isSaving}
            onBlur={(e) => {
              if (e.target.value !== value) {
                onChange(e.target.value);
              }
            }}
          />
          <FieldDescription className="text-xs text-muted-foreground/70">
            <span className="text-muted-foreground">
              {field.description || ""}
            </span>
            {field.example && (
              <p className="font-mono mt-0.5">
                Example: <span className="text-muted-foreground">{field.example}</span>
              </p>
            )}
          </FieldDescription>
        </Field>
      );

    case "FIELD_TYPE_NUMBER":
      return (
        <Field>
          <FieldLabel htmlFor={field.name}>
            {field.label || field.name || ""}
          </FieldLabel>
          <Input
            type="number"
            value={value}
            placeholder={field.placeholder}
            className="h-7 text-xs max-w-32"
            disabled={disabled || isSaving}
            onBlur={(e) => {
              if (e.target.value !== value) {
                onChange(e.target.value);
              }
            }}
          />
          <FieldDescription className="text-xs text-muted-foreground/70">
            <span className="text-muted-foreground">
              {field.description || ""}
            </span>
            {field.example && (
              <p className="font-mono mt-0.5">
                Example: <span className="text-muted-foreground">{field.example}</span>
              </p>
            )}
          </FieldDescription>
        </Field>
      );

    case "FIELD_TYPE_CODE":
      return (
        <Field>
          <FieldLabel htmlFor={field.name}>
            {field.label || field.name || ""}
          </FieldLabel>
          <textarea
          value={value}
          placeholder={field.placeholder ?? "# Nix expression..."}
          rows={5}
          className="w-full max-w-lg rounded-md border border-border bg-muted/50 px-3 py-2 text-xs font-mono leading-relaxed resize-y focus:outline-none focus:ring-1 focus:ring-ring disabled:opacity-50"
          disabled={disabled || isSaving}
          spellCheck={false}
          onBlur={(e) => {
            if (e.target.value !== value) {
              onChange(e.target.value);
            }
          }}
        />
          <FieldDescription className="text-xs text-muted-foreground/70">
            <span className="text-muted-foreground">
              {field.description || ""}
            </span>
            {field.example && (
              <p className="font-mono mt-0.5">
                Example: <span className="text-muted-foreground">{field.example}</span>
              </p>
            )}
          </FieldDescription>
        </Field>
      );

    case "FIELD_TYPE_STRING":
    default:
      return (
        // <Input
        //   value={value}
        //   placeholder={field.placeholder}
        //   className="h-7 text-xs max-w-sm"
        //   disabled={disabled || isSaving}
        //   onBlur={(e) => {
        //     if (e.target.value !== value) {
        //       onChange(e.target.value);
        //     }
        //   }}
        // />
        <Field>
          <FieldLabel htmlFor={field.name}>
            {field.label || field.name || ""}
          </FieldLabel>
          <Input
          id={field.name} type="text" placeholder={field.placeholder ?? ""}
            disabled={disabled || isSaving}
          onBlur={(e) => {
            if (e.target.value !== value) {
              onChange(e.target.value);
            }
          }}
         />
          <FieldDescription className="text-xs text-muted-foreground/70">
            <span className="text-muted-foreground">
              {field.description || ""}
            </span>
            {field.example && (
              <p className="font-mono mt-0.5">
                Example: <span className="text-muted-foreground">{field.example}</span>
              </p>
            )}
          </FieldDescription>
        </Field>
      );
  }
}
