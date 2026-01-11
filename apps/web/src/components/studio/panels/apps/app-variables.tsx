"use client";

import { useState } from "react";
import { ChevronDown, ChevronRight, Variable } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import type { AppVariable } from "@/lib/types";
import { AppVariableType } from "@stackpanel/proto";

interface AppVariablesProps {
  /** Variables linked to this app (map of variable name to AppVariable) */
  variables: Record<string, AppVariable> | undefined;
}

/**
 * Helper to get display label for variable type
 */
function getTypeLabel(type: AppVariableType | number): string {
  switch (type) {
    case AppVariableType.LITERAL:
    case 1:
      return "literal";
    case AppVariableType.VARIABLE:
    case 2:
      return "variable";
    case AppVariableType.VALS:
    case 3:
      return "vals";
    default:
      return "unknown";
  }
}

/**
 * Helper to determine if a variable is a secret based on name patterns
 */
function isSecretVariable(varName: string): boolean {
  const secretPatterns = ["SECRET", "KEY", "PASSWORD", "TOKEN", "CREDENTIAL"];
  return secretPatterns.some((p) => varName.toUpperCase().includes(p));
}

/**
 * Component to display linked variables for an app
 */
export function AppVariables({ variables }: AppVariablesProps) {
  const [isOpen, setIsOpen] = useState(false);

  const variableEntries = Object.entries(variables ?? {});

  if (variableEntries.length === 0) {
    return (
      <span className="text-muted-foreground text-xs">No variables linked</span>
    );
  }

  const secretCount = variableEntries.filter(([name]) =>
    isSecretVariable(name),
  ).length;

  return (
    <div>
      <Button
        variant="ghost"
        size="sm"
        className="h-auto gap-1 p-1 text-xs"
        onClick={() => setIsOpen(!isOpen)}
      >
        {isOpen ? (
          <ChevronDown className="h-3 w-3" />
        ) : (
          <ChevronRight className="h-3 w-3" />
        )}
        <Variable className="h-3 w-3 text-accent" />
        <span>
          {variableEntries.length} variable
          {variableEntries.length !== 1 ? "s" : ""}
          {secretCount > 0 && (
            <span className="ml-1 text-yellow-400">
              ({secretCount} secret{secretCount !== 1 ? "s" : ""})
            </span>
          )}
        </span>
      </Button>
      {isOpen && (
        <div className="mt-2 space-y-1">
          {variableEntries.map(([varName, variable]) => {
            const isSecret = isSecretVariable(varName);
            return (
              <div
                key={varName}
                className="flex items-center gap-2 rounded-md bg-secondary/50 px-2 py-1 text-xs"
              >
                <Variable className="h-3 w-3 text-muted-foreground" />
                <code className="font-mono">{variable.key || varName}</code>
                <Badge
                  variant="outline"
                  className={
                    isSecret
                      ? "border-yellow-500/30 text-yellow-400"
                      : "border-border"
                  }
                >
                  {getTypeLabel(variable.type)}
                </Badge>
                {isSecret && <span className="text-yellow-400">●</span>}
                {variable.value && !isSecret && (
                  <span className="ml-auto text-muted-foreground truncate max-w-32">
                    = {variable.value}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
