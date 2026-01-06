"use client";

import { useState, useMemo } from "react";
import {
  Key,
  Loader2,
  Plus,
  Search,
  Server,
  Settings,
  Sparkles,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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
import { useVariables, useAppsUsingVariable } from "@/lib/use-nix-config";
import type { Variable } from "@/lib/types";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";

const VARIABLE_TYPES = [
  {
    value: "secret",
    label: "Secret",
    description: "Sensitive value stored encrypted",
    icon: Key,
    color: "bg-red-500/20 text-red-400",
  },
  {
    value: "config",
    label: "Config",
    description: "Non-sensitive configuration",
    icon: Settings,
    color: "bg-blue-500/20 text-blue-400",
  },
  {
    value: "computed",
    label: "Computed",
    description: "Derived from other config",
    icon: Sparkles,
    color: "bg-purple-500/20 text-purple-400",
  },
  {
    value: "service",
    label: "Service",
    description: "Auto-generated from service",
    icon: Server,
    color: "bg-green-500/20 text-green-400",
  },
];

function getTypeConfig(type: string) {
  return VARIABLE_TYPES.find((t) => t.value === type) ?? VARIABLE_TYPES[1];
}

interface VariableFormState {
  name: string;
  description: string;
  type: "secret" | "config" | "computed" | "service";
  required: boolean;
  sensitive: boolean;
  default: string;
  options: string;
  service: string;
}

const defaultFormState: VariableFormState = {
  name: "",
  description: "",
  type: "config",
  required: false,
  sensitive: false,
  default: "",
  options: "",
  service: "",
};

function VariableUsageInfo({ variableId }: { variableId: string }) {
  const { data: apps, isLoading } = useAppsUsingVariable(variableId);

  if (isLoading) {
    return <span className="text-muted-foreground text-xs">Loading...</span>;
  }

  if (!apps || apps.length === 0) {
    return (
      <span className="text-muted-foreground text-xs">Not used by any app</span>
    );
  }

  return (
    <div className="flex flex-wrap gap-1">
      {apps.map((app) => (
        <Badge key={app.id} variant="outline" className="text-xs">
          {app.name}
        </Badge>
      ))}
    </div>
  );
}

export function VariablesPanel() {
  const { token } = useAgentContext();
  const { data: variables, isLoading, error, refetch } = useVariables();

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedType, setSelectedType] = useState<string | null>(null);
  const [formState, setFormState] =
    useState<VariableFormState>(defaultFormState);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [newVariableId, setNewVariableId] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  // Filter variables based on search and type
  const filteredVariables = useMemo(() => {
    if (!variables) return {};

    return Object.entries(variables).reduce(
      (acc, [id, variable]) => {
        const matchesSearch =
          !searchQuery ||
          variable.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
          variable.description
            .toLowerCase()
            .includes(searchQuery.toLowerCase());

        const matchesType = !selectedType || variable.type === selectedType;

        if (matchesSearch && matchesType) {
          acc[id] = variable;
        }
        return acc;
      },
      {} as Record<string, Variable>,
    );
  }, [variables, searchQuery, selectedType]);

  // Group filtered variables by type
  const filteredGrouped = useMemo(() => {
    const result: Record<string, Array<Variable & { id: string }>> = {};

    for (const [id, variable] of Object.entries(filteredVariables)) {
      const type = variable.type ?? "config";
      if (!result[type]) {
        result[type] = [];
      }
      result[type].push({ ...variable, id });
    }

    // Sort variables within each group alphabetically
    for (const type of Object.keys(result)) {
      result[type].sort((a, b) => a.name.localeCompare(b.name));
    }

    return result;
  }, [filteredVariables]);

  const handleAddVariable = async () => {
    if (!newVariableId.trim() || !token) {
      toast.error(
        !token ? "Not connected to agent" : "Please enter a variable name",
      );
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const variablesClient = client.mapEntity<Variable>("variables");

      const exists = await variablesClient.has(newVariableId);
      if (exists) {
        toast.error(`Variable "${newVariableId}" already exists`);
        setIsSaving(false);
        return;
      }

      const newVariable: Variable = {
        name: formState.name || newVariableId,
        description: formState.description || "",
        type: formState.type,
        required: formState.required || undefined,
        sensitive: formState.sensitive || undefined,
        default: formState.default || undefined,
        options: formState.options
          ? formState.options.split(",").map((s) => s.trim())
          : undefined,
        service: formState.type === "service" ? formState.service : undefined,
      };

      await variablesClient.set(newVariableId, newVariable);
      toast.success(`Created variable "${newVariableId}"`);
      setDialogOpen(false);
      setNewVariableId("");
      setFormState(defaultFormState);
      refetch();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to create variable",
      );
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (error) {
    return (
      <Card>
        <CardContent className="py-8">
          <p className="text-center text-destructive">
            Error loading variables: {error.message}
          </p>
        </CardContent>
      </Card>
    );
  }

  const totalVariables = variables ? Object.keys(variables).length : 0;
  const typeOrder = ["secret", "config", "computed", "service"];
  const types = typeOrder.filter((t) => filteredGrouped[t]?.length > 0);

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold">Variables</h2>
          <p className="text-muted-foreground text-sm">
            {totalVariables} variable{totalVariables !== 1 ? "s" : ""} defined
          </p>
        </div>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <Button
            onClick={() => setDialogOpen(true)}
            className="bg-accent text-accent-foreground hover:bg-accent/90"
            disabled={!token}
          >
            <Plus className="mr-2 h-4 w-4" />
            Add Variable
          </Button>
          <DialogContent className="max-w-lg">
            <DialogHeader>
              <DialogTitle>Add New Variable</DialogTitle>
              <DialogDescription>
                Create a new environment variable that can be linked to apps.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="variable-id">Variable Name</Label>
                <Input
                  id="variable-id"
                  placeholder="e.g., DATABASE_URL, API_KEY"
                  value={newVariableId}
                  onChange={(e) =>
                    setNewVariableId(
                      e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, "_"),
                    )
                  }
                  className="font-mono"
                />
                <p className="text-muted-foreground text-xs">
                  Environment variable name (SCREAMING_SNAKE_CASE)
                </p>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="variable-description">Description</Label>
                <Textarea
                  id="variable-description"
                  placeholder="What is this variable used for?"
                  value={formState.description}
                  onChange={(e) =>
                    setFormState((s) => ({ ...s, description: e.target.value }))
                  }
                  rows={2}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="variable-type">Type</Label>
                <Select
                  value={formState.type}
                  onValueChange={(value) =>
                    setFormState((s) => ({
                      ...s,
                      type: value as VariableFormState["type"],
                      sensitive: value === "secret" ? true : s.sensitive,
                    }))
                  }
                >
                  <SelectTrigger>
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
                  <Label htmlFor="variable-service">Service</Label>
                  <Input
                    id="variable-service"
                    placeholder="e.g., postgres, redis"
                    value={formState.service}
                    onChange={(e) =>
                      setFormState((s) => ({ ...s, service: e.target.value }))
                    }
                  />
                </div>
              )}
              <div className="grid gap-2">
                <Label htmlFor="variable-default">
                  Default Value (optional)
                </Label>
                <Input
                  id="variable-default"
                  placeholder="Default value if not set"
                  value={formState.default}
                  onChange={(e) =>
                    setFormState((s) => ({ ...s, default: e.target.value }))
                  }
                  type={formState.sensitive ? "password" : "text"}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="variable-options">Options (optional)</Label>
                <Input
                  id="variable-options"
                  placeholder="e.g., development, staging, production"
                  value={formState.options}
                  onChange={(e) =>
                    setFormState((s) => ({ ...s, options: e.target.value }))
                  }
                />
                <p className="text-muted-foreground text-xs">
                  Comma-separated list of valid values
                </p>
              </div>
              <div className="flex items-center gap-6">
                <div className="flex items-center gap-2">
                  <Checkbox
                    id="variable-required"
                    checked={formState.required}
                    onCheckedChange={(checked) =>
                      setFormState((s) => ({ ...s, required: !!checked }))
                    }
                  />
                  <Label
                    htmlFor="variable-required"
                    className="text-sm font-normal"
                  >
                    Required
                  </Label>
                </div>
                <div className="flex items-center gap-2">
                  <Checkbox
                    id="variable-sensitive"
                    checked={formState.sensitive}
                    onCheckedChange={(checked) =>
                      setFormState((s) => ({ ...s, sensitive: !!checked }))
                    }
                  />
                  <Label
                    htmlFor="variable-sensitive"
                    className="text-sm font-normal"
                  >
                    Sensitive (mask in UI)
                  </Label>
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button
                onClick={handleAddVariable}
                disabled={isSaving || !newVariableId.trim()}
                className="bg-accent text-accent-foreground hover:bg-accent/90"
              >
                {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Add Variable
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {/* Search and Filter */}
      <div className="flex gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search variables..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9"
          />
        </div>
        <Select
          value={selectedType ?? "all"}
          onValueChange={(value) =>
            setSelectedType(value === "all" ? null : value)
          }
        >
          <SelectTrigger className="w-45">
            <SelectValue placeholder="All types" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All types</SelectItem>
            {VARIABLE_TYPES.map((t) => (
              <SelectItem key={t.value} value={t.value}>
                <div className="flex items-center gap-2">
                  <t.icon className="h-4 w-4" />
                  {t.label}
                </div>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Variables by Type */}
      <div className="space-y-4">
        {types.length === 0 ? (
          <Card>
            <CardContent className="py-8 text-center">
              <Key className="mx-auto h-12 w-12 text-muted-foreground/50" />
              <p className="mt-2 text-muted-foreground">
                {searchQuery || selectedType
                  ? "No variables match your search"
                  : "No variables defined yet"}
              </p>
            </CardContent>
          </Card>
        ) : (
          types.map((type) => {
            const typeConfig = getTypeConfig(type);
            const typeVariables = filteredGrouped[type] ?? [];
            const TypeIcon = typeConfig.icon;

            return (
              <div key={type} className="space-y-2">
                <div className="flex items-center gap-2">
                  <TypeIcon className="h-4 w-4 text-muted-foreground" />
                  <h3 className="font-medium">{typeConfig.label}</h3>
                  <Badge variant="secondary" className="text-xs">
                    {typeVariables.length}
                  </Badge>
                </div>
                <div className="grid gap-2">
                  {typeVariables.map((variable) => (
                    <Card key={variable.id}>
                      <CardContent className="flex items-center justify-between p-4">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2">
                            <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-sm">
                              {variable.name}
                            </code>
                            {variable.required && (
                              <Badge variant="outline" className="text-xs">
                                required
                              </Badge>
                            )}
                            {variable.sensitive && (
                              <Badge
                                variant="outline"
                                className="border-yellow-500/30 text-yellow-500 text-xs"
                              >
                                sensitive
                              </Badge>
                            )}
                          </div>
                          <p className="text-muted-foreground text-sm">
                            {variable.description}
                          </p>
                          <VariableUsageInfo variableId={variable.id} />
                        </div>
                        <Badge className={typeConfig.color}>
                          {typeConfig.label}
                        </Badge>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
