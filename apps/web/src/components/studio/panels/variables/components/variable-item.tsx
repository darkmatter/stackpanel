"use client";

import { Button } from "@ui/button";
import {
  ChevronRight,
  Cpu,
  Eye,
  EyeOff,
  Loader2,
  Pencil,
  Trash2,
} from "lucide-react";
import {
  getTypeConfig,
  isReadOnlyVariable,
  type VariablesBackend,
} from "../constants";
import { EditVariableDialog } from "../edit-variable-dialog";
import { VariableUsageInfo } from "../variable-usage-info";
import { useVariablesUIStore } from "../store/variables-ui-store";

interface VariableItemProps {
  variable: {
    id: string;
    value: string;
    name: string;
    envKey: string;
  };
  isExpanded: boolean;
  onToggleExpand: (id: string) => void;
  onEditSecret: (id: string, key: string) => void;
  onDeleteSecret: (id: string) => void;
  onRevealSecret: (id: string) => void;
  backend: VariablesBackend;
  token: string | null;
  onSuccess?: () => void;
}

export function VariableItem({
  variable,
  isExpanded,
  onToggleExpand,
  onEditSecret,
  onDeleteSecret,
  onRevealSecret,
  backend,
  token,
  onSuccess,
}: VariableItemProps) {
  const revealedSecrets = useVariablesUIStore(
    (state: any) => state.revealedSecrets,
  );
  const revealedSecret = revealedSecrets[variable.id];
  const typeConfig = getTypeConfig(variable.id, variable.value, backend);
  const TypeIcon = typeConfig.icon;

  return (
    <div className="rounded-lg border border-border bg-card transition-colors hover:border-primary/50">
      <div className="p-4">
        <div className="flex items-start gap-3">
          <button
            type="button"
            onClick={() => onToggleExpand(variable.id)}
            className="mt-0.5 text-muted-foreground"
          >
            <ChevronRight
              className={`h-4 w-4 transition-transform ${
                isExpanded ? "rotate-90" : ""
              }`}
            />
          </button>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1 flex-wrap">
              <TypeIcon
                className={`h-6 w-6 text-muted-foreground ${typeConfig.color} rounded-full p-1`}
              />
              <code className="text-sm font-semibold font-mono">
                {variable.name}
              </code>
              {isReadOnlyVariable(variable.id) && (
                <span
                  className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded bg-none text-amber-600 dark:text-amber-400 border border-amber-500/20"
                  title={`Computed from ${variable.id}`}
                >
                  <Cpu className="h-3 w-3" />
                  Computed
                </span>
              )}
            </div>
            <p className="text-sm text-muted-foreground">
              {typeConfig.description}
            </p>
          </div>
          {/* Edit button for non-computed variables */}
          {!isReadOnlyVariable(variable.id) &&
            (typeConfig.value === "secret" ? (
              <div className="flex items-center gap-1">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => onEditSecret(variable.id, variable.envKey)}
                  disabled={!token}
                  className="h-7 px-2 text-xs"
                >
                  <Pencil className="h-3 w-3 mr-1" />
                  Edit
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => onDeleteSecret(variable.id)}
                  disabled={!token}
                  className="h-7 px-2 text-xs text-destructive hover:text-destructive"
                >
                  <Trash2 className="h-3 w-3" />
                </Button>
              </div>
            ) : (
              <EditVariableDialog
                variable={{
                  id: variable.id,
                  value: variable.value,
                }}
                onSuccess={onSuccess ?? (() => {})}
              />
            ))}
        </div>
      </div>

      {isExpanded && (
        <div className="border-t border-border px-4 py-4 bg-muted/30 space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1">
              <p className="text-xs font-medium text-muted-foreground">
                Environment Key
              </p>
              <p className="text-sm font-mono">{variable.envKey}</p>
            </div>
            <div className="space-y-1">
              <p className="text-xs font-medium text-muted-foreground">Value</p>
              <div className="flex items-center gap-2">
                {typeConfig.value === "secret" ? (
                  <>
                    <p className="text-sm font-mono flex-1 break-all">
                      {revealedSecret?.value || "••••••••••••••••"}
                    </p>
                    {/* Show/Hide button for secrets */}
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-6 px-2 text-xs shrink-0"
                      onClick={(e) => {
                        e.stopPropagation();
                        onRevealSecret(variable.id);
                      }}
                      disabled={revealedSecret?.loading}
                    >
                      {revealedSecret?.loading ? (
                        <Loader2 className="h-3 w-3 animate-spin" />
                      ) : revealedSecret?.value ? (
                        <>
                          <EyeOff className="h-3 w-3 mr-1" />
                          Hide
                        </>
                      ) : (
                        <>
                          <Eye className="h-3 w-3 mr-1" />
                          Show
                        </>
                      )}
                    </Button>
                    {/* Edit button for secrets */}
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-6 px-2 text-xs shrink-0"
                      onClick={(e) => {
                        e.stopPropagation();
                        onEditSecret(variable.id, variable.envKey);
                      }}
                    >
                      <Pencil className="h-3 w-3 mr-1" />
                      Edit
                    </Button>
                  </>
                ) : (
                  <p className="text-sm font-mono">{variable.value || "—"}</p>
                )}
              </div>
              {revealedSecret?.value && (
                <p className="text-xs text-muted-foreground mt-1">
                  Auto-hides in 30 seconds
                </p>
              )}
            </div>
            <div className="space-y-1">
              <p className="text-xs font-medium text-muted-foreground">
                Type Details
              </p>
              <p className="text-sm text-muted-foreground">
                {typeConfig.description}
              </p>
            </div>
            {isReadOnlyVariable(variable.id) && (
              <div className="space-y-1">
                <p className="text-xs font-medium text-muted-foreground">
                  Source
                </p>
                <p className="text-sm font-mono text-blue-600 dark:text-blue-400">
                  {variable.id.startsWith("/computed/services/")
                    ? "Service"
                    : "Computed"}
                </p>
              </div>
            )}
          </div>
          <div>
            <p className="text-xs font-medium text-muted-foreground mb-2">
              Used by
            </p>
            <VariableUsageInfo variableId={variable.id} />
          </div>
        </div>
      )}
    </div>
  );
}
