"use client";

import { VariableType } from "@stackpanel/proto";
import { Input } from "@ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "@ui/popover";
import { ToggleGroup, ToggleGroupItem } from "@ui/toggle-group";
import {
  Calculator,
  Check,
  ChevronDown,
  Eye,
  EyeOff,
  Lock,
  Pencil,
  Plus,
  Trash2,
  Type,
  VariableIcon,
  X,
} from "lucide-react";
import { useMemo, useRef, useState } from "react";

interface DisplayVariable {
  envKey: string;
  variableId: string;
  variableKey: string;
  type: VariableType | null;
  description: string;
  value?: string;
  environments: string[];
  isSecret: boolean;
}

interface AvailableVariable {
  id: string;
  key: string;
  type: VariableType | null;
}

interface AppVariablesSectionProps {
  /** Regular variables for this app */
  variables: DisplayVariable[];
  /** Secret variables for this app */
  secrets: DisplayVariable[];
  /** Available environment options */
  environmentOptions: string[];
  /** All available workspace variables that can be linked */
  availableVariables?: AvailableVariable[];
  /** Callback when a new variable mapping is added (variableId is null for literals) */
  onAddVariable?: (
    envKey: string,
    variableId: string | null,
    environments: string[],
    literalValue?: string,
  ) => void;
  /** Callback when a variable mapping is updated */
  onUpdateVariable?: (
    oldEnvKey: string,
    newEnvKey: string,
    variableId: string | null,
    environments: string[],
    literalValue?: string,
  ) => void;
  /** Callback when a variable mapping is deleted */
  onDeleteVariable?: (envKey: string) => void;
  /** Callback when environments list is updated */
  onUpdateEnvironments?: (environments: string[]) => void;
  /** Whether actions are disabled */
  disabled?: boolean;
}

type EditMode = "add" | "edit";

/**
 * Component to display and manage the variables section for an app.
 * Shows variables/secrets with environment filtering and show/hide values toggle.
 */
export function AppVariablesSection({
  variables,
  secrets,
  environmentOptions,
  availableVariables = [],
  onAddVariable,
  onUpdateVariable,
  onDeleteVariable,
  onUpdateEnvironments,
  disabled,
}: AppVariablesSectionProps) {
  const [showEnvValues, setShowEnvValues] = useState(false);
  const [environmentFilter, setEnvironmentFilter] = useState<string[]>([]);

  // Environment editing state
  const [isEditingEnvironments, setIsEditingEnvironments] = useState(false);
  const [editedEnvironments, setEditedEnvironments] = useState<string[]>([]);
  const [newEnvName, setNewEnvName] = useState("");
  const newEnvInputRef = useRef<HTMLInputElement>(null);

  // Editing state
  const [editMode, setEditMode] = useState<EditMode | null>(null);
  const [editingEnvKey, setEditingEnvKey] = useState<string | null>(null); // Original env key when editing
  const [newEnvKey, setNewEnvKey] = useState("");
  const [selectedVariableId, setSelectedVariableId] = useState<string | null>(
    null,
  );
  const [isLiteralMode, setIsLiteralMode] = useState(false);
  const [literalValue, setLiteralValue] = useState("");
  const [variableSearchOpen, setVariableSearchOpen] = useState(false);
  const [variableSearch, setVariableSearch] = useState("");
  const envKeyInputRef = useRef<HTMLInputElement>(null);
  const literalInputRef = useRef<HTMLInputElement>(null);

  const filteredVariables = variables.filter((variable) => {
    if (environmentFilter.length === 0) return true;
    if (variable.environments.length === 0) return true;
    return variable.environments.some((env) => environmentFilter.includes(env));
  });

  const filteredSecrets = secrets.filter((secret) => {
    if (environmentFilter.length === 0) return true;
    if (secret.environments.length === 0) return true;
    return secret.environments.some((env) => environmentFilter.includes(env));
  });

  // Filter out already-linked variables from available options (except when editing that variable)
  const linkedVariableIds = useMemo(() => {
    const ids = new Set<string>();
    for (const v of variables) {
      // Don't exclude the currently editing variable
      if (editMode === "edit" && editingEnvKey === v.envKey) continue;
      ids.add(v.variableId);
    }
    for (const s of secrets) {
      if (editMode === "edit" && editingEnvKey === s.envKey) continue;
      ids.add(s.variableId);
    }
    return ids;
  }, [variables, secrets, editMode, editingEnvKey]);

  const unusedVariables = useMemo(() => {
    return availableVariables.filter((v) => !linkedVariableIds.has(v.id));
  }, [availableVariables, linkedVariableIds]);

  const filteredUnusedVariables = useMemo(() => {
    if (!variableSearch) return unusedVariables;
    const search = variableSearch.toLowerCase();
    return unusedVariables.filter(
      (v) =>
        v.key.toLowerCase().includes(search) ||
        v.id.toLowerCase().includes(search),
    );
  }, [unusedVariables, variableSearch]);

  const selectedVariable = useMemo(() => {
    if (!selectedVariableId) return null;
    return availableVariables.find((v) => v.id === selectedVariableId) ?? null;
  }, [availableVariables, selectedVariableId]);

  const resetEditState = () => {
    setEditMode(null);
    setEditingEnvKey(null);
    setNewEnvKey("");
    setSelectedVariableId(null);
    setIsLiteralMode(false);
    setLiteralValue("");
    setVariableSearch("");
    setVariableSearchOpen(false);
  };

  // Environment editing handlers
  const handleStartEditingEnvironments = () => {
    setIsEditingEnvironments(true);
    // Ensure all environment names are strings (fixes "0" vs 0 type issues)
    setEditedEnvironments(environmentOptions.map((e) => String(e)));
    setNewEnvName("");
  };

  const handleCancelEditingEnvironments = () => {
    setIsEditingEnvironments(false);
    setEditedEnvironments([]);
    setNewEnvName("");
  };

  const handleSaveEnvironments = () => {
    if (onUpdateEnvironments && editedEnvironments.length > 0) {
      // Filter out any invalid environment names (empty strings, "0", numeric strings that look like indices)
      const validEnvs = editedEnvironments.filter(
        (e) => e && String(e).trim() && !/^\d+$/.test(String(e)),
      );
      // Only save if we have valid environments, otherwise keep the current ones
      if (validEnvs.length > 0) {
        onUpdateEnvironments(validEnvs);
      } else {
        onUpdateEnvironments(
          editedEnvironments.filter((e) => e && String(e).trim()),
        );
      }
    }
    setIsEditingEnvironments(false);
    setEditedEnvironments([]);
    setNewEnvName("");
  };

  const handleAddEnvironment = () => {
    const trimmed = newEnvName.trim().toLowerCase();
    // Don't allow numeric-only environment names (like "0", "1", etc.)
    if (
      trimmed &&
      !editedEnvironments.includes(trimmed) &&
      !/^\d+$/.test(trimmed)
    ) {
      setEditedEnvironments([...editedEnvironments, trimmed]);
      setNewEnvName("");
      setTimeout(() => newEnvInputRef.current?.focus(), 0);
    }
  };

  const handleRemoveEnvironment = (env: string) => {
    // Don't allow removing the last environment
    if (editedEnvironments.length > 1) {
      // Use String() to ensure type-safe comparison (handles "0" vs 0 issues)
      const envStr = String(env);
      setEditedEnvironments(
        editedEnvironments.filter((e) => String(e) !== envStr),
      );
    }
  };

  const handleEnvKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter") {
      e.preventDefault();
      handleAddEnvironment();
    } else if (e.key === "Escape") {
      handleCancelEditingEnvironments();
    }
  };

  const handleStartAdding = () => {
    setEditMode("add");
    setEditingEnvKey(null);
    setNewEnvKey("");
    setSelectedVariableId(null);
    setIsLiteralMode(false);
    setLiteralValue("");
    setVariableSearch("");
    // Focus the input after render
    setTimeout(() => envKeyInputRef.current?.focus(), 0);
  };

  const handleStartEditing = (variable: DisplayVariable) => {
    setEditMode("edit");
    setEditingEnvKey(variable.envKey);
    setNewEnvKey(variable.envKey);

    // Check if it's a literal (no variableId) or linked variable
    if (variable.variableId) {
      setSelectedVariableId(variable.variableId);
      setIsLiteralMode(false);
      setLiteralValue("");
    } else {
      setSelectedVariableId(null);
      setIsLiteralMode(true);
      setLiteralValue(variable.value ?? "");
    }

    setVariableSearch("");
    // Focus the input after render
    setTimeout(() => envKeyInputRef.current?.focus(), 0);
  };

  const handleCancelEditing = () => {
    resetEditState();
  };

  const handleConfirm = () => {
    if (!newEnvKey.trim()) return;
    if (!isLiteralMode && !selectedVariableId) return;
    if (isLiteralMode && !literalValue.trim()) return;

    // Use selected environments, or all if none selected
    const envs =
      environmentFilter.length > 0 ? environmentFilter : environmentOptions;

    if (editMode === "add") {
      if (!onAddVariable) return;

      if (isLiteralMode) {
        onAddVariable(
          newEnvKey.trim().toUpperCase(),
          null,
          envs,
          literalValue.trim(),
        );
      } else {
        onAddVariable(
          newEnvKey.trim().toUpperCase(),
          selectedVariableId!,
          envs,
        );
      }
    } else if (editMode === "edit" && editingEnvKey) {
      if (!onUpdateVariable) return;

      if (isLiteralMode) {
        onUpdateVariable(
          editingEnvKey,
          newEnvKey.trim().toUpperCase(),
          null,
          envs,
          literalValue.trim(),
        );
      } else {
        onUpdateVariable(
          editingEnvKey,
          newEnvKey.trim().toUpperCase(),
          selectedVariableId!,
          envs,
        );
      }
    }

    resetEditState();
  };

  const handleDelete = () => {
    if (editMode !== "edit" || !editingEnvKey || !onDeleteVariable) return;
    onDeleteVariable(editingEnvKey);
    resetEditState();
  };

  const handleSelectVariable = (variableId: string) => {
    setSelectedVariableId(variableId);
    setIsLiteralMode(false);
    setLiteralValue("");
    setVariableSearchOpen(false);
    setVariableSearch("");

    // Auto-fill env key from variable key if empty (only when adding)
    if (!newEnvKey && editMode === "add") {
      const variable = availableVariables.find((v) => v.id === variableId);
      if (variable?.key) {
        setNewEnvKey(variable.key.toUpperCase());
      }
    }
  };

  const handleSelectLiteral = () => {
    setIsLiteralMode(true);
    setSelectedVariableId(null);
    setVariableSearchOpen(false);
    setVariableSearch("");
    // Focus the literal input after render
    setTimeout(() => literalInputRef.current?.focus(), 0);
  };

  const canConfirm =
    newEnvKey.trim() &&
    ((isLiteralMode && literalValue.trim()) ||
      (!isLiteralMode && selectedVariableId));

  const isEditing = editMode !== null;

  // Render the edit/add interface
  const renderEditInterface = () => (
    <div className="flex items-center gap-0.5 rounded-md border border-primary/10 bg-background text-xs overflow-hidden">
      {/* Env Key Input */}
      <Input
        ref={envKeyInputRef}
        value={newEnvKey}
        onChange={(e) => setNewEnvKey(e.target.value.toUpperCase())}
        placeholder="ENV_KEY"
        className="h-8 w-28 border-0 rounded-none bg-transparent text-xs font-mono focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
      />

      {/* Subtle divider */}
      <div className="w-px h-5 bg-border/50" />

      {/* Variable Selector or Literal Input */}
      {isLiteralMode ? (
        <Input
          ref={literalInputRef}
          value={literalValue}
          onChange={(e) => setLiteralValue(e.target.value)}
          placeholder="Enter value..."
          className="h-8 w-40 border-0 rounded-none bg-transparent text-xs font-mono focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
        />
      ) : (
        <Popover open={variableSearchOpen} onOpenChange={setVariableSearchOpen}>
          <PopoverTrigger
            render={(props) => (
              <button
                {...props}
                type="button"
                className="flex items-center gap-1.5 h-8 px-2 min-w-32 hover:bg-muted/50 transition-colors"
              >
                {selectedVariable ? (
                  <>
                    {selectedVariable.type === VariableType.SECRET ? (
                      <Lock className="h-3 w-3 text-orange-500 shrink-0" />
                    ) : (
                      <VariableIcon className="h-3 w-3 text-blue-500 shrink-0" />
                    )}
                    <span className="truncate">{selectedVariable.key}</span>
                  </>
                ) : (
                  <span className="text-muted-foreground">
                    Select variable...
                  </span>
                )}
                <ChevronDown className="h-3 w-3 text-muted-foreground ml-auto shrink-0" />
              </button>
            )}
          />
          <PopoverContent className="w-56 p-0" align="start">
            <div className="p-2 border-b border-border">
              <Input
                value={variableSearch}
                onChange={(e) => setVariableSearch(e.target.value)}
                placeholder="Search variables..."
                className="h-7 text-xs"
              />
            </div>
            <div className="max-h-48 overflow-y-auto p-1">
              {/* Add Literal option */}
              <button
                type="button"
                onClick={handleSelectLiteral}
                className="w-full flex items-center gap-2 px-2 py-1.5 rounded text-xs hover:bg-muted transition-colors text-left mb-1 pb-2"
              >
                <Type className="h-3 w-3 text-emerald-500 shrink-0" />
                <span className="font-medium">Add Literal</span>
                <span className="text-muted-foreground ml-auto text-[10px]">
                  raw value
                </span>
              </button>
              <button
                type="button"
                onClick={() => {
                  window.open("/studio/variables?action=new", "_blank");
                }}
                className="w-full flex items-center gap-2 px-2 py-1.5 rounded text-xs hover:bg-muted transition-colors text-left border-b border-border/50 mb-1 pb-2"
              >
                <VariableIcon className="h-3 w-3 text-blue-500 shrink-0" />
                <span className="font-medium">Add Variable</span>
                <span className="text-muted-foreground ml-auto text-[10px]">
                  Opens in new window
                </span>
              </button>
              {filteredUnusedVariables.length === 0 ? (
                <p className="text-xs text-muted-foreground px-2 py-3 text-center">
                  {unusedVariables.length === 0
                    ? "No variables available"
                    : "No matching variables"}
                </p>
              ) : (
                filteredUnusedVariables.map((variable) => (
                  <button
                    key={variable.id}
                    type="button"
                    onClick={() => handleSelectVariable(variable.id)}
                    className="w-full flex text-gray-300 text-shadow-accent-foreground items-center gap-2 px-2 py-1.5 rounded font-mono text-xs hover:bg-muted transition-colors text-left"
                  >
                    {variable.type === VariableType.SECRET ? (
                      <Lock className="h-3 w-3 text-orange-500 shrink-0" />
                    ) : (
                      <VariableIcon className="h-3 w-3 text-blue-500 shrink-0" />
                    )}
                    <span className="truncate font-medium">{variable.key}</span>
                  </button>
                ))
              )}
            </div>
          </PopoverContent>
        </Popover>
      )}

      {/* Action buttons */}
      <div className="flex items-center border-l border-border/50">
        {editMode === "edit" && onDeleteVariable && (
          <button
            type="button"
            onClick={handleDelete}
            className="h-8 w-8 flex items-center justify-center hover:bg-destructive/10 text-muted-foreground hover:text-destructive transition-colors"
            title="Delete variable"
          >
            <Trash2 className="h-3.5 w-3.5" />
          </button>
        )}
        <button
          type="button"
          onClick={handleConfirm}
          disabled={!canConfirm}
          className="h-8 w-8 flex items-center justify-center hover:bg-emerald-500/10 text-emerald-500 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          title={editMode === "edit" ? "Save changes" : "Add variable"}
        >
          <Check className="h-3.5 w-3.5" />
        </button>
        <button
          type="button"
          onClick={handleCancelEditing}
          className="h-8 w-8 flex items-center justify-center hover:bg-destructive/10 text-muted-foreground hover:text-destructive transition-colors"
          title="Cancel"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );

  // Render a variable badge (clickable to edit)
  const renderVariableBadge = (
    variable: DisplayVariable,
    isSecret: boolean,
  ) => {
    const isCurrentlyEditing =
      editMode === "edit" && editingEnvKey === variable.envKey;
    const isComputed = variable.type === VariableType.VALS;

    // If this variable is being edited, show the edit interface instead
    if (isCurrentlyEditing) {
      return renderEditInterface();
    }

    return (
      <button
        key={`${variable.envKey}-${variable.variableId}`}
        type="button"
        onClick={() => !disabled && handleStartEditing(variable)}
        disabled={disabled || isEditing}
        className="flex items-center gap-2 px-3 py-1.5 rounded-md border border-border bg-background text-xs hover:border-primary/50 hover:bg-muted/30 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isSecret ? (
          <Lock className="h-3 w-3 text-orange-500" />
        ) : isComputed ? (
          <Calculator className="h-3 w-3 text-purple-500" />
        ) : (
          <VariableIcon className="h-3 w-3 text-blue-500" />
        )}
        <span className="font-medium">{variable.envKey}</span>
        {!isSecret && variable.value && (
          <>
            <span className="text-muted-foreground">=</span>
            <span className="text-muted-foreground font-mono truncate max-w-50">
              {showEnvValues ? variable.value : "••••••"}
            </span>
          </>
        )}
        {isSecret && <span className="text-muted-foreground">••••••</span>}
      </button>
    );
  };

  return (
    <div className="space-y-3">
      <div className="text-xs font-medium text-primary">Variables</div>
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          {isEditingEnvironments ? (
            <div className="flex items-center gap-1 rounded-md border border-primary/20 bg-background p-1">
              {editedEnvironments.map((env) => (
                <div
                  key={env}
                  className="flex items-center gap-1 px-2 py-0.5 rounded bg-muted text-xs"
                >
                  <span>{env}</span>
                  <button
                    type="button"
                    onClick={() => handleRemoveEnvironment(env)}
                    disabled={editedEnvironments.length <= 1}
                    className="text-muted-foreground hover:text-destructive disabled:opacity-30 disabled:cursor-not-allowed"
                    title={
                      editedEnvironments.length <= 1
                        ? "At least one environment required"
                        : "Remove environment"
                    }
                  >
                    <X className="h-3 w-3" />
                  </button>
                </div>
              ))}
              <Input
                ref={newEnvInputRef}
                value={newEnvName}
                onChange={(e) => setNewEnvName(e.target.value.toLowerCase())}
                onKeyDown={handleEnvKeyDown}
                placeholder="new env..."
                className="h-6 w-20 border-0 bg-transparent text-xs focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
              />
              <button
                type="button"
                onClick={handleAddEnvironment}
                disabled={
                  !newEnvName.trim() ||
                  editedEnvironments.includes(newEnvName.trim().toLowerCase())
                }
                className="h-6 w-6 flex items-center justify-center text-primary hover:bg-primary/10 rounded disabled:opacity-30 disabled:cursor-not-allowed"
                title="Add environment"
              >
                <Plus className="h-3 w-3" />
              </button>
              <div className="w-px h-4 bg-border mx-1" />
              <button
                type="button"
                onClick={handleSaveEnvironments}
                className="h-6 w-6 flex items-center justify-center text-emerald-500 hover:bg-emerald-500/10 rounded"
                title="Save environments"
              >
                <Check className="h-3 w-3" />
              </button>
              <button
                type="button"
                onClick={handleCancelEditingEnvironments}
                className="h-6 w-6 flex items-center justify-center text-muted-foreground hover:text-destructive hover:bg-destructive/10 rounded"
                title="Cancel"
              >
                <X className="h-3 w-3" />
              </button>
            </div>
          ) : (
            <>
              <ToggleGroup
                type="multiple"
                value={environmentFilter}
                onValueChange={setEnvironmentFilter}
                className="gap-0"
                variant="secondary"
              >
                {environmentOptions.map((env) => (
                  <ToggleGroupItem
                    key={env}
                    value={env}
                    variant="secondary"
                    size="xs"
                  >
                    {env}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
              {onUpdateEnvironments && !disabled && (
                <button
                  type="button"
                  onClick={handleStartEditingEnvironments}
                  className="p-1 text-muted-foreground hover:text-foreground transition-colors"
                  title="Edit environments"
                >
                  <Pencil className="h-3 w-3" />
                </button>
              )}
            </>
          )}
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowEnvValues(!showEnvValues)}
            className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            {showEnvValues ? (
              <>
                <EyeOff className="h-3 w-3" />
                <span>Hide</span>
              </>
            ) : (
              <>
                <Eye className="h-3 w-3" />
                <span>Show</span>
              </>
            )}
          </button>
        </div>
      </div>
      <div className="flex flex-wrap gap-2">
        {/* Render filtered variables */}
        {filteredVariables.map((variable) =>
          renderVariableBadge(variable, false),
        )}

        {/* Render filtered secrets */}
        {filteredSecrets.map((secret) => renderVariableBadge(secret, true))}

        {/* Add interface (when adding new) */}
        {editMode === "add" && renderEditInterface()}

        {/* Add button (when not editing) */}
        {!isEditing && (
          <button
            onClick={handleStartAdding}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-xs text-muted-foreground hover:text-foreground"
            disabled={disabled || !onAddVariable}
          >
            <Plus className="h-3 w-3" />
            <span>Add variable</span>
          </button>
        )}
      </div>
    </div>
  );
}
