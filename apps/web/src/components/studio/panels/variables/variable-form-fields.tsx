"use client";

import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { VARIABLE_TYPES } from "./constants";
import type { VariableFormState } from "./types";

interface VariableFormFieldsProps {
  formState: VariableFormState;
  onFormChange: (updates: Partial<VariableFormState>) => void;
  /** Optional ID field for "add" mode - not shown in edit mode */
  showIdField?: boolean;
  variableId?: string;
  onVariableIdChange?: (id: string) => void;
  /** ID prefix for form elements to ensure uniqueness */
  idPrefix?: string;
}

export function VariableFormFields({
  formState,
  onFormChange,
  showIdField = false,
  variableId = "",
  onVariableIdChange,
  idPrefix = "variable",
}: VariableFormFieldsProps) {
  return (
    <div className="grid gap-4">
      {showIdField && onVariableIdChange && (
        <div className="grid gap-2">
          <Label htmlFor={`${idPrefix}-id`}>Variable Name *</Label>
          <Input
            id={`${idPrefix}-id`}
            placeholder="e.g., DATABASE_URL, API_KEY"
            value={variableId}
            onChange={(e) =>
              onVariableIdChange(
                e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, "_")
              )
            }
            className="font-mono"
          />
          <p className="text-muted-foreground text-xs">
            Environment variable name (SCREAMING_SNAKE_CASE)
          </p>
        </div>
      )}

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-description`}>Description</Label>
        <Textarea
          id={`${idPrefix}-description`}
          placeholder="What is this variable used for?"
          value={formState.description}
          onChange={(e) => onFormChange({ description: e.target.value })}
          rows={2}
        />
      </div>

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-type`}>Type</Label>
        <Select
          value={formState.type}
          onValueChange={(value) =>
            onFormChange({
              type: value as VariableFormState["type"],
              sensitive: value === "secret" ? true : formState.sensitive,
            })
          }
        >
          <SelectTrigger id={`${idPrefix}-type`}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {VARIABLE_TYPES.map((t) => (
              <SelectItem key={t.value} value={t.value}>
                <div className="flex items-center gap-2">
                  <t.icon className="h-4 w-4" />
                  <span>{t.label}</span>
                  <span className="text-muted-foreground text-xs">
                    - {t.description}
                  </span>
                </div>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {formState.type === "service" && (
        <div className="grid gap-2">
          <Label htmlFor={`${idPrefix}-service`}>Service</Label>
          <Input
            id={`${idPrefix}-service`}
            placeholder="e.g., postgres, redis"
            value={formState.service}
            onChange={(e) => onFormChange({ service: e.target.value })}
          />
        </div>
      )}

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-default`}>Default Value (optional)</Label>
        <Input
          id={`${idPrefix}-default`}
          placeholder="Default value if not set"
          value={formState.default}
          onChange={(e) => onFormChange({ default: e.target.value })}
          type={formState.sensitive ? "password" : "text"}
        />
      </div>

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-options`}>Options (optional)</Label>
        <Input
          id={`${idPrefix}-options`}
          placeholder="e.g., development, staging, production"
          value={formState.options}
          onChange={(e) => onFormChange({ options: e.target.value })}
        />
        <p className="text-muted-foreground text-xs">
          Comma-separated list of valid values
        </p>
      </div>

      <div className="flex items-center gap-6">
        <div className="flex items-center gap-2">
          <Checkbox
            id={`${idPrefix}-required`}
            checked={formState.required}
            onCheckedChange={(checked) =>
              onFormChange({ required: !!checked })
            }
          />
          <Label htmlFor={`${idPrefix}-required`} className="text-sm font-normal">
            Required
          </Label>
        </div>
        <div className="flex items-center gap-2">
          <Checkbox
            id={`${idPrefix}-sensitive`}
            checked={formState.sensitive}
            onCheckedChange={(checked) =>
              onFormChange({ sensitive: !!checked })
            }
          />
          <Label htmlFor={`${idPrefix}-sensitive`} className="text-sm font-normal">
            Sensitive (mask in UI)
          </Label>
        </div>
      </div>
    </div>
  );
}
