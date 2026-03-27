"use client";

import { Card, CardContent } from "@ui/card";
import { ChevronDown, VariableIcon } from "lucide-react";
import type { VariablesBackend } from "../constants";
import { useVariablesUIStore } from "../store/variables-ui-store";
import { useSecretActions } from "../hooks/use-secret-actions";
import { VariablesFilter } from "./variables-filter";
import { VariableItem } from "./variable-item";

interface ManageTabProps {
  filteredVariables: Array<{
    id: string;
    value: string;
    name: string;
    envKey: string;
  }>;
  backend: VariablesBackend;
  token: string | null;
  onSuccess: () => void;
}

export function ManageTab({
  filteredVariables,
  backend,
  token,
  onSuccess,
}: ManageTabProps) {
  // Get store state
  const searchQuery = useVariablesUIStore((state: any) => state.searchQuery);
  const selectedType = useVariablesUIStore((state: any) => state.selectedType);
  const expandedId = useVariablesUIStore((state: any) => state.expandedId);
  const toggleExpanded = useVariablesUIStore(
    (state: any) => state.toggleExpanded,
  );
  const setEditingSecret = useVariablesUIStore(
    (state: any) => state.setEditingSecret,
  );

  // Get secret actions
  const { revealSecret, deleteSecret } = useSecretActions(onSuccess);

  const emptyStateMessage =
    searchQuery || selectedType !== "all"
      ? "No variables match your search"
      : "No variables defined yet";

  return (
    <div className="mt-6 space-y-6">
      <VariablesFilter filteredCount={filteredVariables.length} />

      <div className="space-y-2">
        {filteredVariables.length === 0 ? (
          <Card>
            <CardContent className="py-10 text-center text-muted-foreground">
              <VariableIcon className="mx-auto h-10 w-10 text-muted-foreground/50" />
              <p className="mt-3 text-sm">{emptyStateMessage}</p>
            </CardContent>
          </Card>
        ) : (
          filteredVariables.map((variable) => (
            <VariableItem
              key={variable.id}
              variable={variable}
              isExpanded={expandedId === variable.id}
              onToggleExpand={toggleExpanded}
              onEditSecret={(id, key) => setEditingSecret({ id, key })}
              onDeleteSecret={deleteSecret}
              onRevealSecret={revealSecret}
              backend={backend}
              token={token}
              onSuccess={onSuccess}
            />
          ))
        )}
      </div>

      <div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4">
        <h4 className="mb-2 flex items-center gap-2 text-sm font-medium text-blue-600 dark:text-blue-400">
          <ChevronDown className="h-4 w-4" />
          Variables vs Secrets
        </h4>
        <ul className="ml-6 list-disc space-y-1 text-sm text-muted-foreground">
          <li>
            <strong>Configs</strong> are regular environment values like URLs
            and feature flags.
          </li>
          <li>
            <strong>Secrets</strong> are sensitive values that should stay
            encrypted.
          </li>
          <li>
            Computed and service variables are generated automatically based on
            config.
          </li>
        </ul>
      </div>
    </div>
  );
}
