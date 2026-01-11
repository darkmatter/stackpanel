"use client";

import { useMemo, useState } from "react";
import {
  ChevronDown,
  ChevronRight,
  Loader2,
  Search,
  VariableIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { useVariables } from "@/lib/use-nix-config";
import {
  VARIABLE_TYPES,
  getTypeConfig,
  type VariableTypeName,
} from "./constants";
import { VariableUsageInfo } from "./variable-usage-info";
import { AddVariableDialog } from "./add-variable-dialog";

export function VariablesPanel() {
  const { data: variables, isLoading, error, refetch } = useVariables();

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedType, setSelectedType] = useState<VariableTypeName | "all">(
    "all",
  );
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const variablesList = useMemo(() => {
    if (!variables) return [];
    return Object.entries(variables).map(([id, variable]) => ({
      ...variable,
      name: variable.key ?? id,
      description: variable.description ?? "",
      id,
    }));
  }, [variables]);

  // Filter variables based on search and type
  const filteredVariables = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();

    return variablesList
      .filter((variable) => {
        const matchesSearch =
          !query ||
          variable.name.toLowerCase().includes(query) ||
          variable.description.toLowerCase().includes(query) ||
          variable.id.toLowerCase().includes(query);

        const matchesType =
          selectedType.includes("all") ||
          // @ts-ignore
          selectedType.includes(variable.type as string);

        return matchesSearch && matchesType;
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [variablesList, searchQuery, selectedType]);

  const toggleExpanded = (id: string) => {
    setExpandedId((current) => (current === id ? null : id));
  };

  const totalVariables = variablesList.length;
  const emptyStateMessage =
    searchQuery || selectedType !== "all"
      ? "No variables match your search"
      : "No variables defined yet";

  if (isLoading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="border-destructive/40">
        <CardContent className="space-y-4 py-8 text-center">
          <p className="text-destructive">
            Error loading variables: {error.message}
          </p>
          <Button variant="outline" onClick={refetch}>
            Retry
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-semibold mb-1">Variables & Secrets</h2>
          <p className="text-sm text-muted-foreground">
            {totalVariables} variable{totalVariables !== 1 ? "s" : ""} defined
          </p>
        </div>
        <AddVariableDialog onSuccess={refetch} />
      </div>

      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-3">
          <div className="relative flex-1 min-w-60">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Search variables..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>
          <ToggleGroup
            type="single"
            variant="outline"
            value={selectedType}
            onValueChange={(value) => {
              setSelectedType((value || "all") as VariableTypeName | "all");
            }}
            className="flex-wrap "
          >
            <ToggleGroupItem value="all" size="sm" className="text-[11px] px-2">
              All
            </ToggleGroupItem>
            {VARIABLE_TYPES.map((type) => {
              const TypeIcon = type.icon;
              return (
                <ToggleGroupItem
                  key={type.value}
                  value={type.value}
                  size="sm"
                  className="text-[11px] px-6"
                >
                  <TypeIcon className="size-4 opacity-80 shrink-0" />
                  {type.label}
                </ToggleGroupItem>
              );
            })}
          </ToggleGroup>
          <div className="text-xs text-muted-foreground">
            {filteredVariables.length} result
            {filteredVariables.length === 1 ? "" : "s"}
          </div>
        </div>
      </div>

      <div className="space-y-2">
        {filteredVariables.length === 0 ? (
          <Card>
            <CardContent className="py-10 text-center text-muted-foreground">
              <VariableIcon className="mx-auto h-10 w-10 text-muted-foreground/50" />
              <p className="mt-3 text-sm">{emptyStateMessage}</p>
            </CardContent>
          </Card>
        ) : (
          filteredVariables.map((variable) => {
            const typeConfig = getTypeConfig(variable.type);
            const TypeIcon = typeConfig.icon;
            const isExpanded = expandedId === variable.id;

            return (
              <div
                key={variable.id}
                className="rounded-lg border border-border bg-card transition-colors hover:border-primary/50"
              >
                <div className="p-4">
                  <div className="flex items-start gap-3">
                    <button
                      type="button"
                      onClick={() => toggleExpanded(variable.id)}
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
                        <TypeIcon className="h-4 w-4 text-muted-foreground" />
                        <code className="text-sm font-semibold font-mono">
                          {variable.name}
                        </code>
                        <span
                          className={`px-2 py-0.5 text-xs rounded ${typeConfig.color}`}
                        >
                          {typeConfig.label}
                        </span>
                      </div>
                      <p className="text-sm text-muted-foreground">
                        {variable.description || "No description provided."}
                      </p>
                    </div>
                  </div>
                </div>

                {isExpanded && (
                  <div className="border-t border-border px-4 py-4 bg-muted/30 space-y-4">
                    <div className="grid gap-4 sm:grid-cols-2">
                      <div className="space-y-1">
                        <p className="text-xs font-medium text-muted-foreground">
                          Value
                        </p>
                        <p className="text-sm font-mono">
                          {variable.value ?? "—"}
                        </p>
                      </div>
                      <div className="space-y-1">
                        <p className="text-xs font-medium text-muted-foreground">
                          Type Details
                        </p>
                        <p className="text-sm text-muted-foreground">
                          {typeConfig.description}
                        </p>
                      </div>
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
          })
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
