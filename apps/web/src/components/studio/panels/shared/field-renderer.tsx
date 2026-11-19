"use client";

import { Field, FieldDescription, FieldLabel } from "@stackpanel/ui-web/field";
import { useEffect, useId, useState } from "react";
import { FieldInput, type FieldInputProps } from "./editable-field";
import type { NixPanelField } from "./panel-types";

export interface FieldRendererProps {
  field: NixPanelField;
  value: string;
  disabled?: boolean;
  isSaving?: boolean;
  onChange: (value: string) => void;
}

/** Text edits are local until blur; discrete controls commit on selection. */
function DraftInput({ value, onChange, ...props }: FieldInputProps) {
  const [draft, setDraft] = useState(value);
  useEffect(() => setDraft(value), [value]);
  return (
    <FieldInput
      {...props}
      value={draft}
      onChange={setDraft}
      onBlur={() => {
        if (!props.disabled && draft !== value) onChange(draft);
      }}
    />
  );
}

const discreteTypes = [
  "FIELD_TYPE_BOOLEAN",
  "FIELD_TYPE_SELECT",
  "FIELD_TYPE_MULTISELECT",
  "FIELD_TYPE_SECRET_REF",
  "FIELD_TYPE_MARKDOWN",
];

export function FieldRenderer({ field, value, disabled, isSaving, onChange }: FieldRendererProps) {
  const id = useId();
  const example = field.type === "FIELD_TYPE_SECRET_REF" ? undefined : field.example;
  const input = { id, field, value, disabled: disabled || isSaving, onChange };
  return (
    <Field>
      <FieldLabel htmlFor={id}>{field.label ?? field.name}</FieldLabel>
      {discreteTypes.includes(field.type) ? (
        <FieldInput {...input} />
      ) : (
        <DraftInput key={`${field.type}:${field.name}`} {...input} />
      )}
      {(field.description || example) && (
        <FieldDescription className="text-xs">
          {field.description}
          {example && <span className="block font-mono">Example: {example}</span>}
        </FieldDescription>
      )}
    </Field>
  );
}
