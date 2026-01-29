"use client";

/**
 * Self-contained editable field components with inline save functionality.
 *
 * Components:
 * - `EditableField` - Single field with its own save button
 * - `EditableFieldGroup` - Multiple fields with shared save button
 * - `useFieldEditor` - Hook for custom field editing UIs
 *
 * Usage (single field):
 * ```tsx
 * <EditableField
 *   field={{ name: "org", type: "FIELD_TYPE_STRING", label: "Organization" }}
 *   initialValue="my-org"
 *   configPath="stackpanel.deployment.fly.organization"
 * />
 * ```
 *
 * Usage (multiple fields):
 * ```tsx
 * <EditableFieldGroup
 *   fields={[
 *     { field: { name: "org", ... }, initialValue: "my-org", configPath: "..." },
 *     { field: { name: "region", ... }, initialValue: "iad", configPath: "..." },
 *   ]}
 * />
 * ```
 */

import { useState, useEffect, useCallback } from "react";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import { Check, Loader2, RotateCcw, X } from "lucide-react";
import { usePatchNixData } from "@/lib/use-agent";
import type { NixFieldOption } from "./panel-types";

// =============================================================================
// Types
// =============================================================================

/** Helper to normalize field options to {value, label} format */
function normalizeOption(opt: NixFieldOption): { value: string; label: string } {
  if (typeof opt === "string") {
    return { value: opt, label: opt };
  }
  return opt;
}

/** Field configuration */
export interface EditableFieldConfig {
  name: string;
  type: string;
  label?: string | null;
  placeholder?: string | null;
  description?: string | null;
  options?: NixFieldOption[];
}

/** Save target configuration */
export interface FieldSaveTarget {
  /**
   * Full Nix config path for saving (e.g., "stackpanel.deployment.fly.organization").
   * If provided, saves to entity="config", key="_root".
   */
  configPath?: string | null;
  /**
   * Entity type for per-entity patching (e.g., "apps").
   * Used with entityKey and editPath.
   */
  entity?: string;
  /**
   * Entity key for per-entity patching (e.g., app name "web").
   */
  entityKey?: string;
  /**
   * Path within the entity for patching (e.g., "go.mainPackage").
   * Used with entity and entityKey.
   */
  editPath?: string | null;
}

/** Configuration for a single field in a group */
export interface EditableFieldItem extends FieldSaveTarget {
  field: EditableFieldConfig;
  initialValue: string;
}

// =============================================================================
// useFieldEditor Hook - Shared logic for field editing
// =============================================================================

export interface UseFieldEditorOptions {
  fields: EditableFieldItem[];
  onSaved?: (values: Record<string, string>) => void;
}

export interface FieldEditorState {
  /** Current local values keyed by field name */
  values: Record<string, string>;
  /** Original/saved values keyed by field name */
  savedValues: Record<string, string>;
  /** Whether any field has unsaved changes */
  isDirty: boolean;
  /** Whether a save is in progress */
  isSaving: boolean;
  /** Error message if save failed */
  error: string | null;
  /** Update a single field's local value */
  setValue: (name: string, value: string) => void;
  /** Reset all fields to saved values */
  reset: () => void;
  /** Save all dirty fields */
  save: () => Promise<void>;
  /** Save a single field immediately */
  saveField: (name: string) => Promise<void>;
  /** Get the field config by name */
  getField: (name: string) => EditableFieldItem | undefined;
}

export function useFieldEditor({
  fields,
  onSaved,
}: UseFieldEditorOptions): FieldEditorState {
  const patchNixData = usePatchNixData();

  // Initialize state from fields
  const initialValues = Object.fromEntries(
    fields.map((f) => [f.field.name, f.initialValue])
  );

  const [values, setValues] = useState<Record<string, string>>(initialValues);
  const [savedValues, setSavedValues] = useState<Record<string, string>>(initialValues);
  const [error, setError] = useState<string | null>(null);

  // Sync with external changes (e.g., SSE updates)
  useEffect(() => {
    const newInitialValues = Object.fromEntries(
      fields.map((f) => [f.field.name, f.initialValue])
    );
    // Only update if saved values changed externally
    const hasExternalChanges = fields.some(
      (f) => f.initialValue !== savedValues[f.field.name]
    );
    if (hasExternalChanges) {
      // Check if we have local unsaved changes
      const hasDirtyFields = fields.some(
        (f) => values[f.field.name] !== savedValues[f.field.name]
      );
      if (!hasDirtyFields) {
        setValues(newInitialValues);
        setSavedValues(newInitialValues);
      }
    }
  }, [fields, savedValues, values]);

  const isDirty = fields.some((f) => values[f.field.name] !== savedValues[f.field.name]);

  const setValue = useCallback((name: string, value: string) => {
    setValues((prev) => ({ ...prev, [name]: value }));
    setError(null);
  }, []);

  const reset = useCallback(() => {
    setValues(savedValues);
    setError(null);
  }, [savedValues]);

  const getValueType = (fieldType: string) => {
    switch (fieldType) {
      case "FIELD_TYPE_BOOLEAN":
        return "bool";
      case "FIELD_TYPE_NUMBER":
        return "number";
      case "FIELD_TYPE_MULTISELECT":
        return "list";
      case "FIELD_TYPE_JSON":
        return "object";
      default:
        return "string";
    }
  };

  const saveField = useCallback(
    async (name: string) => {
      const fieldConfig = fields.find((f) => f.field.name === name);
      if (!fieldConfig) return;

      const value = values[name];
      if (value === savedValues[name]) return; // Not dirty

      const { configPath, entity, entityKey, editPath, field } = fieldConfig;
      const canSave = !!(configPath || (entity && entityKey && editPath));
      if (!canSave) return;

      const valueType = getValueType(field.type);
      const jsonValue = valueType === "string" ? JSON.stringify(value) : value;

      try {
        setError(null);
        await patchNixData.mutateAsync({
          entity: configPath ? "config" : entity!,
          key: configPath ? "_root" : entityKey!,
          path: configPath || editPath!,
          value: jsonValue,
          valueType,
        });
        setSavedValues((prev) => ({ ...prev, [name]: value }));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to save");
        throw err;
      }
    },
    [fields, values, savedValues, patchNixData]
  );

  const save = useCallback(async () => {
    const dirtyFields = fields.filter(
      (f) => values[f.field.name] !== savedValues[f.field.name]
    );

    if (dirtyFields.length === 0) return;

    setError(null);
    const newSavedValues = { ...savedValues };

    // Save each dirty field sequentially
    // TODO: Could be optimized with a bulk API
    for (const fieldConfig of dirtyFields) {
      const { configPath, entity, entityKey, editPath, field } = fieldConfig;
      const name = field.name;
      const value = values[name];

      const canSave = !!(configPath || (entity && entityKey && editPath));
      if (!canSave) continue;

      const valueType = getValueType(field.type);
      const jsonValue = valueType === "string" ? JSON.stringify(value) : value;

      try {
        await patchNixData.mutateAsync({
          entity: configPath ? "config" : entity!,
          key: configPath ? "_root" : entityKey!,
          path: configPath || editPath!,
          value: jsonValue,
          valueType,
        });
        newSavedValues[name] = value;
      } catch (err) {
        setError(err instanceof Error ? err.message : `Failed to save ${name}`);
        // Update partial saves
        setSavedValues(newSavedValues);
        throw err;
      }
    }

    setSavedValues(newSavedValues);
    onSaved?.(newSavedValues);
  }, [fields, values, savedValues, patchNixData, onSaved]);

  const getField = useCallback(
    (name: string) => fields.find((f) => f.field.name === name),
    [fields]
  );

  return {
    values,
    savedValues,
    isDirty,
    isSaving: patchNixData.isPending,
    error,
    setValue,
    reset,
    save,
    saveField,
    getField,
  };
}

// =============================================================================
// FieldInput - Just the input, no save logic
// =============================================================================

export interface FieldInputProps {
  field: EditableFieldConfig;
  value: string;
  onChange: (value: string) => void;
  onKeyDown?: (e: React.KeyboardEvent) => void;
  disabled?: boolean;
}

export function FieldInput({
  field,
  value,
  onChange,
  onKeyDown,
  disabled = false,
}: FieldInputProps) {
  switch (field.type) {
    case "FIELD_TYPE_BOOLEAN":
      return (
        <div className="flex items-center gap-2">
          <Switch
            checked={value === "true"}
            disabled={disabled}
            onCheckedChange={(checked) => onChange(String(checked))}
          />
          <span className="text-xs text-muted-foreground">
            {value === "true" ? "Enabled" : "Disabled"}
          </span>
        </div>
      );

    case "FIELD_TYPE_SELECT": {
      const options = (field.options ?? []).map(normalizeOption);
      return (
        <Select value={value} disabled={disabled} onValueChange={onChange}>
          <SelectTrigger size="sm" className="w-full">
            <SelectValue placeholder={field.placeholder ?? "Select..."} />
          </SelectTrigger>
          <SelectContent>
            {options.map((opt) => (
              <SelectItem key={opt.value} value={opt.value}>
                {opt.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      );
    }

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
                    <X className="h-2.5 w-2.5" />
                  </button>
                )}
              </Badge>
            ))}
          </div>
          {!disabled && (
            <Input
              placeholder={field.placeholder ?? "Add item..."}
              className="h-7 text-xs"
              disabled={disabled}
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

    case "FIELD_TYPE_CODE":
      return (
        <textarea
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder={field.placeholder ?? "# Nix expression..."}
          rows={5}
          className="w-full rounded-md border border-border bg-muted/50 px-3 py-2 text-xs font-mono leading-relaxed resize-y focus:outline-none focus:ring-1 focus:ring-ring disabled:opacity-50"
          disabled={disabled}
          spellCheck={false}
        />
      );

    case "FIELD_TYPE_NUMBER":
      return (
        <Input
          type="number"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder={field.placeholder ?? undefined}
          className="h-7 text-xs"
          disabled={disabled}
        />
      );

    case "FIELD_TYPE_JSON":
      return (
        <Input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder={field.placeholder ?? "JSON..."}
          className="h-7 text-xs font-mono"
          disabled={disabled}
        />
      );

    case "FIELD_TYPE_STRING":
    default:
      return (
        <Input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder={field.placeholder ?? undefined}
          className="h-7 text-xs"
          disabled={disabled}
        />
      );
  }
}

// =============================================================================
// EditableField - Single field with inline save
// =============================================================================

export interface EditableFieldProps extends FieldSaveTarget {
  field: EditableFieldConfig;
  initialValue: string;
  disabled?: boolean;
  showLabel?: boolean;
  /** Auto-save on change for boolean/select types (default: true) */
  autoSave?: boolean;
  onSaved?: (newValue: string) => void;
}

export function EditableField({
  field,
  initialValue,
  configPath,
  entity,
  entityKey,
  editPath,
  disabled = false,
  showLabel = true,
  autoSave = true,
  onSaved,
}: EditableFieldProps) {
  const editor = useFieldEditor({
    fields: [{ field, initialValue, configPath, entity, entityKey, editPath }],
    onSaved: (values) => onSaved?.(values[field.name]),
  });

  const value = editor.values[field.name] ?? "";
  const canSave = !!(configPath || (entity && entityKey && editPath));
  const isEditable = canSave && !disabled;
  const fieldIsDirty = value !== editor.savedValues[field.name];

  // For auto-save types (boolean, select), save immediately on change
  const isAutoSaveType =
    autoSave &&
    (field.type === "FIELD_TYPE_BOOLEAN" || field.type === "FIELD_TYPE_SELECT");

  const handleChange = (newValue: string) => {
    editor.setValue(field.name, newValue);
    if (isAutoSaveType && canSave) {
      // Defer to next tick so state updates first
      setTimeout(() => {
        editor.saveField(field.name).catch(() => {
          // Error is already set in editor state
        });
      }, 0);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey && fieldIsDirty) {
      e.preventDefault();
      editor.save();
    } else if (e.key === "Escape" && fieldIsDirty) {
      e.preventDefault();
      editor.reset();
    }
  };

  const showSaveButtons = fieldIsDirty && isEditable && !isAutoSaveType;

  return (
    <div className="space-y-1.5">
      {showLabel && (
        <div className="flex items-center gap-2">
          <Label className="text-xs font-medium">
            {field.label ?? field.name}
          </Label>
          {!canSave && (
            <Badge
              variant="outline"
              className="text-[9px] px-1 py-0 text-muted-foreground"
            >
              read-only
            </Badge>
          )}
        </div>
      )}
      {field.description && (
        <p className="text-xs text-muted-foreground">{field.description}</p>
      )}
      <div className="flex items-center gap-2">
        <div className="flex-1">
          <FieldInput
            field={field}
            value={value}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            disabled={disabled || editor.isSaving || !isEditable}
          />
        </div>
        {showSaveButtons && (
          <div className="flex items-center gap-1">
            <Button
              size="sm"
              variant="ghost"
              className="h-7 w-7 p-0"
              onClick={editor.reset}
              disabled={editor.isSaving}
              title="Reset (Esc)"
            >
              <RotateCcw className="h-3.5 w-3.5" />
            </Button>
            <Button
              size="sm"
              className="h-7 px-2 gap-1"
              onClick={() => editor.save()}
              disabled={editor.isSaving}
              title="Save (Enter)"
            >
              {editor.isSaving ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <Check className="h-3.5 w-3.5" />
              )}
              <span className="text-xs">Save</span>
            </Button>
          </div>
        )}
        {editor.isSaving && isAutoSaveType && (
          <Loader2 className="h-3.5 w-3.5 animate-spin text-muted-foreground" />
        )}
      </div>
      {editor.error && (
        <p className="text-xs text-destructive">{editor.error}</p>
      )}
    </div>
  );
}

// =============================================================================
// EditableFieldGroup - Multiple fields with shared save
// =============================================================================

export interface EditableFieldGroupProps {
  /** Array of field configurations */
  fields: EditableFieldItem[];
  /** Title for the group (optional) */
  title?: string;
  /** Description for the group (optional) */
  description?: string;
  /** Whether all fields are disabled */
  disabled?: boolean;
  /** Layout: vertical (stacked) or horizontal (side by side) */
  layout?: "vertical" | "horizontal";
  /** Callback after all fields saved */
  onSaved?: (values: Record<string, string>) => void;
}

export function EditableFieldGroup({
  fields,
  title,
  description,
  disabled = false,
  layout = "vertical",
  onSaved,
}: EditableFieldGroupProps) {
  const editor = useFieldEditor({ fields, onSaved });

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey && editor.isDirty) {
      e.preventDefault();
      editor.save();
    } else if (e.key === "Escape" && editor.isDirty) {
      e.preventDefault();
      editor.reset();
    }
  };

  return (
    <div className="space-y-4">
      {(title || description) && (
        <div className="space-y-1">
          {title && <h4 className="text-sm font-medium">{title}</h4>}
          {description && (
            <p className="text-xs text-muted-foreground">{description}</p>
          )}
        </div>
      )}

      <div
        className={
          layout === "horizontal"
            ? "grid grid-cols-2 gap-4"
            : "space-y-4"
        }
      >
        {fields.map((fieldConfig) => {
          const { field } = fieldConfig;
          const value = editor.values[field.name] ?? "";
          const canSave = !!(
            fieldConfig.configPath ||
            (fieldConfig.entity && fieldConfig.entityKey && fieldConfig.editPath)
          );

          return (
            <div key={field.name} className="space-y-1.5">
              <div className="flex items-center gap-2">
                <Label className="text-xs font-medium">
                  {field.label ?? field.name}
                </Label>
                {!canSave && (
                  <Badge
                    variant="outline"
                    className="text-[9px] px-1 py-0 text-muted-foreground"
                  >
                    read-only
                  </Badge>
                )}
              </div>
              {field.description && (
                <p className="text-xs text-muted-foreground">
                  {field.description}
                </p>
              )}
              <FieldInput
                field={field}
                value={value}
                onChange={(v) => editor.setValue(field.name, v)}
                onKeyDown={handleKeyDown}
                disabled={disabled || editor.isSaving || !canSave}
              />
            </div>
          );
        })}
      </div>

      {/* Shared save/reset buttons */}
      <div className="flex items-center gap-2 pt-2 border-t">
        {editor.isDirty ? (
          <>
            <Button
              size="sm"
              variant="outline"
              className="h-8 gap-1.5"
              onClick={editor.reset}
              disabled={editor.isSaving}
            >
              <RotateCcw className="h-3.5 w-3.5" />
              Reset
            </Button>
            <Button
              size="sm"
              className="h-8 gap-1.5"
              onClick={() => editor.save()}
              disabled={editor.isSaving}
            >
              {editor.isSaving ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <Check className="h-3.5 w-3.5" />
              )}
              Save Changes
            </Button>
          </>
        ) : (
          <span className="text-xs text-muted-foreground">No changes</span>
        )}
      </div>

      {editor.error && (
        <p className="text-xs text-destructive">{editor.error}</p>
      )}
    </div>
  );
}
