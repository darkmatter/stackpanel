"use client";

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
import { COMMAND_CATEGORIES } from "./constants";
import type { CommandFormState } from "./types";

interface CommandFormFieldsProps {
  formState: CommandFormState;
  onFormChange: (updates: Partial<CommandFormState>) => void;
  /** Optional ID field for "add" mode - not shown in edit mode */
  showIdField?: boolean;
  commandId?: string;
  onCommandIdChange?: (id: string) => void;
  /** ID prefix for form elements to ensure uniqueness */
  idPrefix?: string;
}

export function CommandFormFields({
  formState,
  onFormChange,
  showIdField = false,
  commandId = "",
  onCommandIdChange,
  idPrefix = "command",
}: CommandFormFieldsProps) {
  return (
    <div className="grid gap-4">
      {showIdField && onCommandIdChange && (
        <div className="grid gap-2">
          <Label htmlFor={`${idPrefix}-id`}>Command ID *</Label>
          <Input
            id={`${idPrefix}-id`}
            placeholder="e.g., build, test:unit, deploy:prod"
            value={commandId}
            onChange={(e) => onCommandIdChange(e.target.value)}
            className="font-mono"
          />
          <p className="text-muted-foreground text-xs">
            Unique identifier used to reference this command
          </p>
        </div>
      )}

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-name`}>Display Name</Label>
        <Input
          id={`${idPrefix}-name`}
          placeholder="e.g., Build, Unit Tests, Deploy to Production"
          value={formState.name}
          onChange={(e) => onFormChange({ name: e.target.value })}
        />
      </div>

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-description`}>Description</Label>
        <Textarea
          id={`${idPrefix}-description`}
          placeholder="What does this command do?"
          value={formState.description}
          onChange={(e) => onFormChange({ description: e.target.value })}
          rows={2}
        />
      </div>

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-category`}>Category</Label>
        <Select
          value={formState.category}
          onValueChange={(value) => onFormChange({ category: value })}
        >
          <SelectTrigger id={`${idPrefix}-category`}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {COMMAND_CATEGORIES.map((cat) => (
              <SelectItem key={cat.value} value={cat.value}>
                {cat.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="grid gap-2">
        <Label htmlFor={`${idPrefix}-cmd`}>Command (optional)</Label>
        <Input
          id={`${idPrefix}-cmd`}
          placeholder="e.g., npm run build"
          value={formState.command ?? ""}
          onChange={(e) => onFormChange({ command: e.target.value })}
          className="font-mono"
        />
        <p className="text-muted-foreground text-xs">
          Default command to run. Apps can override this.
        </p>
      </div>
    </div>
  );
}
