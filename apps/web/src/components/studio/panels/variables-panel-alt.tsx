"use client";

import { useState } from "react";
import {
  Plus,
  Trash2,
  Lock,
  VariableIcon,
  Eye,
  EyeOff,
  ChevronDown,
  Copy,
  Check,
  ChevronRight,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { AppSidebar } from "@/components/app-sidebar";
import { AppHeader } from "@/components/app-header";

type Variable = {
  id: string;
  name: string;
  type: "secret" | "variable";
  description: string;
  values: {
    development?: string;
    staging?: string;
    production?: string;
  };
};

const initialVariables: Variable[] = [
  {
    id: "1",
    name: "APP_URL",
    type: "variable",
    description: "The base URL for the application",
    values: {
      development: "http://localhost:3000",
      staging: "https://staging.example.com",
      production: "https://example.com",
    },
  },
  {
    id: "2",
    name: "AUTH_SECRET",
    type: "secret",
    description: "Secret key for authentication",
    values: {
      development: "dev_secret_key_123",
      staging: "stg_secret_key_456",
      production: "prod_secret_key_789",
    },
  },
  {
    id: "3",
    name: "API_URL",
    type: "variable",
    description: "External API endpoint",
    values: {
      development: "http://localhost:4000/api",
      staging: "https://api-staging.example.com",
    },
  },
  {
    id: "4",
    name: "DATABASE_PASSWORD",
    type: "secret",
    description: "Database connection password",
    values: {
      production: "super_secret_password",
    },
  },
];

export default function VariablesPage() {
  const [variables, setVariables] = useState<Variable[]>(initialVariables);
  const [selectedEnvironment, setSelectedEnvironment] = useState("development");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [revealedSecrets, setRevealedSecrets] = useState<Set<string>>(
    new Set(),
  );
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [filterType, setFilterType] = useState<
    ("all" | "secret" | "variable")[]
  >(["all"]);

  const toggleExpanded = (id: string) => {
    setExpandedId(expandedId === id ? null : id);
  };

  const toggleReveal = (id: string) => {
    const newRevealed = new Set(revealedSecrets);
    if (newRevealed.has(id)) {
      newRevealed.delete(id);
    } else {
      newRevealed.add(id);
    }
    setRevealedSecrets(newRevealed);
  };

  const copyValue = (value: string, id: string) => {
    navigator.clipboard.writeText(value);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const deleteVariable = (id: string) => {
    setVariables(variables.filter((v) => v.id !== id));
    if (expandedId === id) {
      setExpandedId(null);
    }
  };

  const filteredVariables = variables.filter((v) => {
    const currentFilter = filterType[0];
    if (currentFilter === "all") return true;
    return v.type === currentFilter;
  });

  return (
    <div className="flex h-screen bg-background">
      <AppSidebar />

      {/* Main Content */}
      <main className="flex-1 flex flex-col overflow-hidden">
        <AppHeader
          title="Variables"
          subtitle="Configure environment-specific values for your apps"
        />

        {/* Content */}
        <div className="flex-1 overflow-auto p-6">
          <div className="max-w-5xl">
            {/* Page Header */}
            <div className="mb-6 flex items-center justify-between">
              <div>
                <h2 className="text-2xl font-semibold mb-1">
                  Variables & Secrets
                </h2>
                <p className="text-sm text-muted-foreground">
                  Configure environment-specific values that can be associated
                  with apps
                </p>
              </div>
              <Button className="gap-2">
                <Plus className="h-4 w-4" />
                Add Variable
              </Button>
            </div>

            {/* Filters */}
            <div className="mb-4 flex items-center gap-3">
              <ToggleGroup
                value={filterType}
                onValueChange={(v) => {
                  if (v.length > 0) {
                    setFilterType([v[v.length - 1]] as typeof filterType);
                  }
                }}
              >
                <ToggleGroupItem
                  value="all"
                  size="sm"
                  className="data-pressed:bg-primary/20 data-pressed:text-primary"
                >
                  All
                </ToggleGroupItem>
                <ToggleGroupItem
                  value="variable"
                  size="sm"
                  className="data-pressed:bg-blue-500/20 data-pressed:text-blue-500"
                >
                  <VariableIcon className="h-3 w-3 mr-1" />
                  Variables
                </ToggleGroupItem>
                <ToggleGroupItem
                  value="secret"
                  size="sm"
                  className="data-pressed:bg-orange-500/20 data-pressed:text-orange-500"
                >
                  <Lock className="h-3 w-3 mr-1" />
                  Secrets
                </ToggleGroupItem>
              </ToggleGroup>
              <div className="text-xs text-muted-foreground">
                {filteredVariables.length}{" "}
                {filteredVariables.length === 1 ? "item" : "items"}
              </div>
            </div>

            {/* Variables List */}
            <div className="space-y-2">
              {filteredVariables.map((variable) => {
                const isExpanded = expandedId === variable.id;
                const isRevealed = revealedSecrets.has(variable.id);
                const environmentValue =
                  variable.values[
                    selectedEnvironment as keyof typeof variable.values
                  ];
                const hasValue = !!environmentValue;

                return (
                  <div
                    key={variable.id}
                    className="border border-border rounded-lg bg-card overflow-hidden hover:border-primary/50 transition-colors"
                  >
                    {/* Variable Header */}
                    <div className="p-4">
                      <div className="flex items-start gap-3">
                        <button
                          onClick={() => toggleExpanded(variable.id)}
                          className="mt-0.5"
                        >
                          <ChevronRight
                            className={`h-4 w-4 text-muted-foreground transition-transform ${
                              isExpanded ? "rotate-90" : ""
                            }`}
                          />
                        </button>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            {variable.type === "secret" ? (
                              <Lock className="h-4 w-4 text-orange-500 flex-shrink-0" />
                            ) : (
                              <VariableIcon className="h-4 w-4 text-blue-500 flex-shrink-0" />
                            )}
                            <h3 className="text-sm font-semibold font-mono">
                              {variable.name}
                            </h3>
                            <span
                              className={`px-2 py-0.5 text-xs rounded ${
                                variable.type === "secret"
                                  ? "bg-orange-500/20 text-orange-600 dark:text-orange-500"
                                  : "bg-blue-500/20 text-blue-600 dark:text-blue-500"
                              }`}
                            >
                              {variable.type}
                            </span>
                          </div>
                          <p className="text-sm text-muted-foreground mb-2">
                            {variable.description}
                          </p>
                          <div className="text-xs text-muted-foreground">
                            Environments:{" "}
                            {Object.entries(variable.values)
                              .filter(([_, value]) => value)
                              .map(([env]) => env)
                              .join(", ") || "none"}
                          </div>
                        </div>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-destructive flex-shrink-0"
                          onClick={() => deleteVariable(variable.id)}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>

                    {/* Expanded Content */}
                    {isExpanded && (
                      <div className="border-t border-border px-4 py-4 bg-muted/30 space-y-4">
                        {(
                          ["development", "staging", "production"] as const
                        ).map((env) => {
                          const value = variable.values[env];
                          const isCopied = copiedId === `${variable.id}-${env}`;

                          return (
                            <div key={env}>
                              <label className="text-xs font-medium text-muted-foreground mb-1.5 block capitalize">
                                {env}
                              </label>
                              <div className="flex gap-2">
                                <div className="flex-1 relative">
                                  <Input
                                    value={value || ""}
                                    onChange={(e) => {
                                      setVariables(
                                        variables.map((v) =>
                                          v.id === variable.id
                                            ? {
                                                ...v,
                                                values: {
                                                  ...v.values,
                                                  [env]: e.target.value,
                                                },
                                              }
                                            : v,
                                        ),
                                      );
                                    }}
                                    type={
                                      variable.type === "secret" && !isRevealed
                                        ? "password"
                                        : "text"
                                    }
                                    placeholder={`${variable.name} for ${env}`}
                                    className="font-mono pr-20"
                                  />
                                  {value && (
                                    <div className="absolute right-2 top-1/2 -translate-y-1/2 flex gap-1">
                                      {variable.type === "secret" && (
                                        <Button
                                          variant="ghost"
                                          size="icon"
                                          className="h-6 w-6"
                                          onClick={() =>
                                            toggleReveal(variable.id)
                                          }
                                        >
                                          {isRevealed ? (
                                            <EyeOff className="h-3 w-3" />
                                          ) : (
                                            <Eye className="h-3 w-3" />
                                          )}
                                        </Button>
                                      )}
                                      <Button
                                        variant="ghost"
                                        size="icon"
                                        className="h-6 w-6"
                                        onClick={() =>
                                          copyValue(
                                            value,
                                            `${variable.id}-${env}`,
                                          )
                                        }
                                      >
                                        {isCopied ? (
                                          <Check className="h-3 w-3 text-green-500" />
                                        ) : (
                                          <Copy className="h-3 w-3" />
                                        )}
                                      </Button>
                                    </div>
                                  )}
                                </div>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                );
              })}

              {/* Add Variable Button */}
              <button className="w-full p-4 border border-dashed border-border rounded-lg hover:border-primary hover:bg-primary/5 transition-colors flex items-center justify-center gap-2 text-muted-foreground hover:text-foreground">
                <Plus className="h-4 w-4" />
                <span className="text-sm font-medium">Add Variable</span>
              </button>
            </div>

            {/* Info Section */}
            <div className="mt-8 p-4 border border-blue-500/20 bg-blue-500/5 rounded-lg">
              <h4 className="text-sm font-medium text-blue-600 dark:text-blue-400 mb-2 flex items-center gap-2">
                <ChevronDown className="h-4 w-4" />
                Variables vs Secrets
              </h4>
              <ul className="text-sm text-muted-foreground space-y-1 ml-6 list-disc">
                <li>
                  <strong>Variables</strong> are regular environment values
                  (URLs, feature flags, etc.) that are not sensitive
                </li>
                <li>
                  <strong>Secrets</strong> are sensitive values (API keys,
                  passwords) that are encrypted and masked by default
                </li>
                <li>
                  Both can have different values per environment (development,
                  staging, production)
                </li>
                <li>
                  Associate variables with apps to make them available as
                  environment variables
                </li>
              </ul>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}
