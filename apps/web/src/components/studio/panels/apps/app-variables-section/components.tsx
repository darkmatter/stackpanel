/**
 * Sub-components for the app variables section.
 *
 * Variable rows match the task row layout: full-width rows with
 * icon | ENV_KEY | border-l | value | actions on hover.
 */
"use client";

import { Button } from "@ui/button";
import { Input } from "@ui/input";
import {
  Calculator,
  Check,
  KeyRound,
  Lock,
  Pencil,
  Trash2,
  VariableIcon,
  X,
} from "lucide-react";
import {
  Combobox,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxList,
} from "@/components/ui/combobox";
import { useMemo, useState, type RefObject } from "react";
import type { AvailableVariable, DisplayVariable, EditMode } from "./types";
import { isSopsReference, isValsReference } from "../utils";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build a vals reference for a variable ID.
 * E.g., "/dev/DATABASE_URL" → "ref+sops://.stackpanel/secrets/dev.yaml#/DATABASE_URL"
 */
function buildValsReference(variableId: string): string {
  const parts = variableId.split("/").filter(Boolean);
  if (parts.length >= 2) {
    const env = parts[0];
    const name = parts.slice(1).join("/");
    return `ref+sops://.stackpanel/secrets/${env}.yaml#/${name}`;
  }
  return `ref+sops://.stackpanel/secrets/dev.yaml#${variableId}`;
}

/**
 * Extract env key suggestion from variable ID.
 * E.g., "/dev/DATABASE_URL" → "DATABASE_URL"
 */
function suggestEnvKey(variableId: string): string {
  const parts = variableId.split("/").filter(Boolean);
  if (parts.length >= 2) {
    return parts[parts.length - 1];
  }
  return variableId.replace(/[^A-Z0-9_]/gi, "_").toUpperCase();
}

/** Return the type icon for a variable */
function VariableTypeIcon({
  isSecret,
  isComputed,
}: {
  isSecret: boolean;
  isComputed: boolean;
}) {
  if (isSecret) return <Lock className="h-3 w-3 text-orange-500" />;
  if (isComputed) return <Calculator className="h-3 w-3 text-purple-500" />;
  return <VariableIcon className="h-3 w-3 text-blue-500" />;
}

// ---------------------------------------------------------------------------
// EditInterface — inline row editor for add / edit
// ---------------------------------------------------------------------------

interface EditInterfaceProps {
  newEnvKey: string;
  setNewEnvKey: (value: string) => void;
  editValue: string;
  setEditValue: (value: string) => void;
  canConfirm: boolean;
  editMode: EditMode | null;
  envKeyInputRef: RefObject<HTMLInputElement | null>;
  literalInputRef: RefObject<HTMLInputElement | null>;
  availableVariables?: AvailableVariable[];
  onConfirm: () => void;
  onCancel: () => void;
  onDelete?: () => void;
}

/** Sentinel value for the "literal" combobox option */
const LITERAL_ID = "__literal__";

export function EditInterface({
  newEnvKey,
  setNewEnvKey,
  editValue,
  setEditValue,
  canConfirm,
  editMode,
  envKeyInputRef,
  literalInputRef,
  availableVariables,
  onConfirm,
  onCancel,
  onDelete,
}: EditInterfaceProps) {
  const [isLiteralMode, setIsLiteralMode] = useState(false);

  /** The combobox item type — an available variable or the sentinel literal option */
  type ComboboxItemType = AvailableVariable & { _isLiteral?: boolean };

  // Build items array with the sentinel literal option appended
  const comboboxItems = useMemo(
    (): ComboboxItemType[] => [
      {
        id: LITERAL_ID,
        name: "Literal or ref+sops://...",
        typeName: "config" as AvailableVariable["typeName"],
        _isLiteral: true,
      },
      ...(availableVariables ?? []),
    ],
    [availableVariables],
  );

  const handleSelectVariable = (variableId: string) => {
    const variable = availableVariables?.find((v) => v.id === variableId);
    if (!variable) return;
    setEditValue(buildValsReference(variable.id));
    if (!newEnvKey) {
      setNewEnvKey(suggestEnvKey(variable.id));
    }
  };

  const handleComboboxChange = (value: ComboboxItemType | null) => {
    if (!value) return;
    if (value.id === LITERAL_ID) {
      // Switch to literal input mode
      setIsLiteralMode(true);
      setEditValue("");
      // Focus the literal input after render
      setTimeout(() => literalInputRef.current?.focus(), 0);
      return;
    }
    // A variable reference was selected
    setIsLiteralMode(false);
    handleSelectVariable(value.id);
  };

  // Custom filter: always show the literal sentinel, normal filter for others
  const filterItem = (item: ComboboxItemType, query: string) => {
    if (item.id === LITERAL_ID) return true; // always show literal option
    if (!query) return true;
    return item.name.toLowerCase().includes(query.toLowerCase());
  };

  return (
    <div className="flex items-center gap-2 px-3 py-1.5 rounded-md border border-primary/30 bg-background text-xs w-full">
      {/* ENV_KEY input */}
      <Input
        ref={envKeyInputRef}
        value={newEnvKey}
        onChange={(e) => setNewEnvKey(e.target.value.toUpperCase())}
        placeholder="ENV_KEY"
        className="h-7 w-45 border-0 bg-transparent! text-xs font-mono font-medium text-primary/80 focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50 p-0"
      />

      {/* Separator */}
      <div className="w-px h-4 bg-border shrink-0" />

      {/* Value area — combobox or literal input */}
      {isLiteralMode ? (
        <Input
          ref={literalInputRef}
          value={editValue}
          onChange={(e) => setEditValue(e.target.value)}
          placeholder="literal value or ref+sops://..."
          className="cursor-pointer h-7 flex-1 border-0 bg-transparent text-xs font-mono text-muted-foreground focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50 p-0"
        />
      ) : (
        <div className="flex items-center gap-1 flex-1 min-w-0 outline-none focus:outline-none focus:shadow-none shadow-none!">
          <Combobox
            items={comboboxItems}
            onValueChange={handleComboboxChange}
            filter={filterItem}
            itemToStringLabel={(item) => item.name}
          >
            <ComboboxInput
              inputGroupVariant="flat"
              placeholder="Select variable or literal..."
              showClear
              className="cursor-pointer outline-none border-none bg-transparent! min-w-96 focus:outline-none cursor-pointer !focus:shadow-none focus:bg-accent/20"
            />
            <ComboboxContent className="outline-none! focus:outline-none! shadow-none! focus:shadow-none! hover:bg-secondary">
              <ComboboxEmpty>No items found.</ComboboxEmpty>
              <ComboboxList className="shadow-none! outline-none! border-none! cursor-pointer bg-background">
                {(item: ComboboxItemType) => {
                  const isLiteral = item.id === LITERAL_ID;
                  return (
                    <ComboboxItem
                      key={item.id}
                      value={item}
                      className="outline-none! focus:outline-none! cursor-pointer hover:bg-secondary/10 focus:bg-secondary/10 data-highlighted:bg-secondary"
                    >
                      <div className="flex items-center gap-2">
                        {isLiteral ? (
                          <KeyRound className="h-3.5 w-3.5 text-muted-foreground" />
                        ) : (
                          <VariableTypeIcon
                            isSecret={item.typeName === "secret"}
                            isComputed={item.typeName === "computed"}
                          />
                        )}
                        <span
                          className={`font-mono text-xs ${isLiteral ? "text-muted-foreground" : ""}`}
                        >
                          {item.name}
                        </span>
                      </div>
                    </ComboboxItem>
                  );
                }}
              </ComboboxList>
            </ComboboxContent>
          </Combobox>
        </div>
      )}

      {/* Action buttons */}
      <div className="flex items-center gap-0.5 shrink-0">
        {editMode === "edit" && onDelete && (
          <Button
            variant="ghost"
            size="icon"
            className="h-6 w-6"
            onClick={onDelete}
            title="Delete variable"
          >
            <Trash2 className="h-3 w-3 text-muted-foreground hover:text-destructive" />
          </Button>
        )}
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={onConfirm}
          disabled={!canConfirm}
          title={editMode === "edit" ? "Save changes" : "Add variable"}
        >
          <Check className="h-3 w-3 text-emerald-500" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={onCancel}
          title="Cancel"
        >
          <X className="h-3 w-3 text-muted-foreground" />
        </Button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// VariableRow — full-width row (matches task row layout)
// ---------------------------------------------------------------------------

interface VariableRowProps {
  variable: DisplayVariable;
  isSecret: boolean;
  isCurrentlyEditing: boolean;
  showEnvValues: boolean;
  disabled?: boolean;
  isEditing: boolean;
  onStartEditing: (variable: DisplayVariable) => void;
  renderEditInterface: () => React.ReactNode;
}

/**
 * Full-width variable row matching the task row style.
 */
export function VariableRow({
  variable,
  isSecret,
  isCurrentlyEditing,
  showEnvValues,
  disabled,
  isEditing,
  onStartEditing,
  renderEditInterface,
}: VariableRowProps) {
  const isComputed =
    isValsReference(variable.value) && !isSopsReference(variable.value);

  if (isCurrentlyEditing) {
    return <>{renderEditInterface()}</>;
  }

  return (
    <div
      className="group flex items-center gap-2 px-3 py-2 rounded-md border border-border bg-background/70 hover:bg-background/10 cursor-pointer"
      onClick={() => !disabled && !isEditing && onStartEditing(variable)}
    >
      <VariableTypeIcon isSecret={isSecret} isComputed={isComputed} />
      <span className="text-xs font-medium min-w-40 text-primary/80 font-mono">
        {variable.envKey}
      </span>
      <span className="text-xs text-muted-foreground font-mono truncate flex-1 border-l pl-4">
        {isSecret ? "••••••" : showEnvValues ? variable.value : "••••••"}
      </span>
      <Pencil className="h-3 w-3 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity shrink-0" />
    </div>
  );
}
