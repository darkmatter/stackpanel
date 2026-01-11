import { useState } from "react";
import {
  X,
  Play,
  Key,
  ChevronDown,
  Trash2,
  Lock,
  Variable,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";

type Environment = "development" | "staging" | "production";

type AvailableTask = {
  name: string;
  defaultScript: string;
  description?: string;
};

type TaskConfig = {
  key: string;
  command: string;
};

type AvailableSecret = {
  id: string;
  name: string;
  type: "secret" | "variable";
  value?: string; // Only for non-secrets
};

type VariableConfig = {
  secretId: string;
  environments: Environment[];
};

type App = {
  id: string;
  name: string;
  badge?: string;
  path: string;
  domain: string;
  tasks: { name: string; description: string }[];
  variables: { name: string; type: "secret" | "variable"; computed: boolean }[];
};

interface AppConfigDrawerProps {
  app: App | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function AppConfigDrawer({
  app,
  open,
  onOpenChange,
}: AppConfigDrawerProps) {
  const [activeTab, setActiveTab] = useState<"tasks" | "variables">("tasks");
  const [selectedEnvironments, setSelectedEnvironments] = useState<
    Environment[]
  >(["development"]);
  const [environment, setEnvironment] = useState<Environment>("development");

  const availableTasks: AvailableTask[] = [
    {
      name: "build",
      defaultScript: "npm run build",
      description: "Build for production",
    },
    {
      name: "dev",
      defaultScript: "npm run dev",
      description: "Start dev server",
    },
    { name: "test", defaultScript: "npm test", description: "Run test suite" },
    { name: "lint", defaultScript: "npm run lint", description: "Lint code" },
    {
      name: "type-check",
      defaultScript: "tsc --noEmit",
      description: "Type checking",
    },
  ];

  const [taskConfigs, setTaskConfigs] = useState<TaskConfig[]>([
    { key: "build", command: "npm run build" },
    { key: "dev", command: "npm run dev -- --turbo" },
  ]);

  const [showTaskSuggestions, setShowTaskSuggestions] = useState<number | null>(
    null,
  );
  const [taskKeyInput, setTaskKeyInput] = useState<{ [index: number]: string }>(
    {},
  );

  const availableSecrets: AvailableSecret[] = [
    {
      id: "1",
      name: "APP_URL",
      type: "variable",
      value: "https://app.example.com",
    },
    { id: "2", name: "AUTH_SECRET", type: "secret" },
    {
      id: "3",
      name: "API_URL",
      type: "variable",
      value: "https://api.example.com",
    },
    {
      id: "4",
      name: "DATABASE_URL",
      type: "variable",
      value: "postgres://localhost:5432/db",
    },
    { id: "5", name: "STRIPE_KEY", type: "secret" },
    {
      id: "6",
      name: "REDIS_URL",
      type: "variable",
      value: "redis://localhost:6379",
    },
  ];

  const [variableConfigs, setVariableConfigs] = useState<VariableConfig[]>([
    { secretId: "1", environments: ["development", "staging", "production"] },
    { secretId: "2", environments: ["development", "staging"] },
    { secretId: "3", environments: ["production"] },
  ]);

  const [showVariableSuggestions, setShowVariableSuggestions] = useState<
    number | null
  >(null);
  const [variableNameInput, setVariableNameInput] = useState<{
    [index: number]: string;
  }>({});

  const removeTask = (index: number) => {
    setTaskConfigs(taskConfigs.filter((_, i) => i !== index));
  };

  const updateTaskKey = (index: number, key: string) => {
    if (index === taskConfigs.length) {
      setTaskConfigs([...taskConfigs, { key, command: "" }]);
    } else {
      const updated = [...taskConfigs];
      updated[index] = { ...updated[index], key };
      setTaskConfigs(updated);
    }
    setTaskKeyInput({ ...taskKeyInput, [index]: key });
  };

  const updateTaskCommand = (index: number, command: string) => {
    if (index === taskConfigs.length) {
      setTaskConfigs([...taskConfigs, { key: "", command }]);
    } else {
      const updated = [...taskConfigs];
      updated[index] = { ...updated[index], command };
      setTaskConfigs(updated);
    }
  };

  const selectPredefinedTask = (index: number, task: AvailableTask) => {
    if (index === taskConfigs.length) {
      setTaskConfigs([
        ...taskConfigs,
        { key: task.name, command: task.defaultScript },
      ]);
    } else {
      const updated = [...taskConfigs];
      updated[index] = { key: task.name, command: task.defaultScript };
      setTaskConfigs(updated);
    }
    setTaskKeyInput({ ...taskKeyInput, [index]: task.name });
    setShowTaskSuggestions(null);
  };

  const getDefaultScript = (key: string): string => {
    const task = availableTasks.find((t) => t.name === key);
    return task?.defaultScript || "";
  };

  const getFilteredTasks = (index: number): AvailableTask[] => {
    const input = taskKeyInput[index] || taskConfigs[index]?.key || "";
    if (!input) return availableTasks;
    return availableTasks.filter((t) =>
      t.name.toLowerCase().includes(input.toLowerCase()),
    );
  };

  const removeVariable = (index: number) => {
    setVariableConfigs(variableConfigs.filter((_, i) => i !== index));
  };

  const updateVariableName = (index: number, name: string) => {
    const secret = availableSecrets.find((s) => s.name === name);
    if (index === variableConfigs.length) {
      if (secret) {
        setVariableConfigs([
          ...variableConfigs,
          { secretId: secret.id, environments: [] },
        ]);
      }
    } else {
      if (secret) {
        const updated = [...variableConfigs];
        updated[index] = { ...updated[index], secretId: secret.id };
        setVariableConfigs(updated);
      }
    }
    setVariableNameInput({ ...variableNameInput, [index]: name });
  };

  const selectPredefinedVariable = (index: number, secret: AvailableSecret) => {
    if (index === variableConfigs.length) {
      setVariableConfigs([
        ...variableConfigs,
        { secretId: secret.id, environments: [] },
      ]);
    } else {
      const updated = [...variableConfigs];
      updated[index] = { ...updated[index], secretId: secret.id };
      setVariableConfigs(updated);
    }
    setVariableNameInput({ ...variableNameInput, [index]: secret.name });
    setShowVariableSuggestions(null);
  };

  const getFilteredVariables = (index: number): AvailableSecret[] => {
    const input = variableNameInput[index] || "";
    const usedSecretIds = variableConfigs
      .filter((_, i) => i !== index)
      .map((v) => v.secretId);
    const availableToAdd = availableSecrets.filter(
      (s) => !usedSecretIds.includes(s.id),
    );

    if (!input) return availableToAdd;
    return availableToAdd.filter((s) =>
      s.name.toLowerCase().includes(input.toLowerCase()),
    );
  };

  const getSecretById = (id: string): AvailableSecret | undefined => {
    return availableSecrets.find((s) => s.id === id);
  };

  const formatEnvironments = (envs: Environment[]): string => {
    if (envs.length === 0) return "No environments";
    const shortNames = {
      development: "dev",
      staging: "stg",
      production: "prod",
    };
    return envs.map((e) => shortNames[e]).join(", ");
  };

  const displayTasks = [...taskConfigs, { key: "", command: "" }];
  const displayVariables = [
    ...variableConfigs,
    { secretId: "", environments: [] as Environment[] },
  ];

  const getFilteredVariablesForEnvironments = (): VariableConfig[] => {
    if (selectedEnvironments.length === 0) return [];
    return variableConfigs.filter((config) =>
      selectedEnvironments.every((env) => config.environments.includes(env)),
    );
  };

  if (!app) return null;

  return (
    <>
      {/* Backdrop */}
      <div
        className={`fixed inset-0 bg-black/50 transition-opacity z-40 ${
          open ? "opacity-100" : "opacity-0 pointer-events-none"
        }`}
        onClick={() => onOpenChange(false)}
      />

      {/* Drawer */}
      <div
        className={`fixed right-0 top-0 h-full w-[600px] bg-background border-l border-border shadow-2xl transform transition-transform duration-300 z-50 flex flex-col ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        {/* Header */}
        <div className="border-b border-border px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold">Configure App</h2>
              {app.badge && (
                <Badge
                  variant="secondary"
                  className="bg-yellow-500/20 text-yellow-600 dark:text-yellow-500"
                >
                  {app.badge}
                </Badge>
              )}
            </div>
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => onOpenChange(false)}
            className="h-8 w-8"
          >
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* App Info */}
        <div className="px-6 py-3 bg-muted/30 border-b border-border">
          <div className="text-sm">
            <div className="font-medium text-foreground mb-1">{app.name}</div>
            <div className="text-xs text-muted-foreground">{app.path}</div>
          </div>
        </div>

        {/* Tabs */}
        <Tabs
          value={activeTab}
          onValueChange={(v) => setActiveTab(v as any)}
          className="flex-1 flex flex-col"
        >
          <div className="px-6 pt-4">
            <TabsList className="w-full">
              <TabsTrigger value="tasks" className="flex-1">
                <Play className="h-4 w-4 mr-2" />
                Tasks
              </TabsTrigger>
              <TabsTrigger value="variables" className="flex-1">
                <Key className="h-4 w-4 mr-2" />
                Variables
              </TabsTrigger>
            </TabsList>
          </div>

          {/* Tasks Tab */}
          <TabsContent
            value="tasks"
            className="flex-1 overflow-auto px-6 py-4 space-y-4 mt-0"
          >
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-medium">Turbo Tasks</h3>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Define task scripts for this app (like package.json scripts)
                  </p>
                </div>
              </div>

              <div className="space-y-2">
                {displayTasks.map((task, index) => {
                  const isEmptyRow = index === taskConfigs.length;
                  return (
                    <div key={index} className="flex items-start gap-2 group">
                      <div className="flex-1 grid grid-cols-[180px_1fr] gap-2">
                        <div className="relative">
                          <div className="relative">
                            <Input
                              value={taskKeyInput[index] ?? task.key}
                              onChange={(e) =>
                                updateTaskKey(index, e.target.value)
                              }
                              onFocus={() => setShowTaskSuggestions(index)}
                              onBlur={() =>
                                setTimeout(
                                  () => setShowTaskSuggestions(null),
                                  200,
                                )
                              }
                              placeholder="Task name"
                              className="h-9 text-sm font-mono pr-8"
                            />
                            <Button
                              variant="ghost"
                              size="icon"
                              className="absolute right-0 top-0 h-9 w-8 text-muted-foreground hover:text-foreground"
                              onClick={() =>
                                setShowTaskSuggestions(
                                  showTaskSuggestions === index ? null : index,
                                )
                              }
                            >
                              <ChevronDown className="h-3.5 w-3.5" />
                            </Button>
                          </div>
                          {showTaskSuggestions === index && (
                            <div className="absolute top-full left-0 right-0 mt-1 bg-popover border border-border rounded-md shadow-lg z-10 max-h-48 overflow-auto">
                              {getFilteredTasks(index).map((availableTask) => (
                                <button
                                  key={availableTask.name}
                                  onClick={() =>
                                    selectPredefinedTask(index, availableTask)
                                  }
                                  className="w-full px-3 py-2 text-left hover:bg-accent text-sm flex items-center justify-between"
                                >
                                  <div className="font-medium font-mono whitespace-pre">
                                    {availableTask.name}
                                  </div>
                                  {availableTask.description && (
                                    <div className="text-xs text-muted-foreground overflow-hidden whitespace-pre text-ellipsis pl-2">
                                      {availableTask.description}
                                    </div>
                                  )}
                                </button>
                              ))}
                              {getFilteredTasks(index).length === 0 && (
                                <div className="px-3 py-2 text-sm text-muted-foreground">
                                  No matching tasks
                                </div>
                              )}
                            </div>
                          )}
                        </div>
                        <Input
                          value={task.command}
                          onChange={(e) =>
                            updateTaskCommand(index, e.target.value)
                          }
                          placeholder={
                            getDefaultScript(task.key) || "npm run ..."
                          }
                          className="h-9 text-sm font-mono"
                        />
                      </div>
                      {!isEmptyRow && (
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => removeTask(index)}
                          className="h-9 w-9 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground hover:text-destructive"
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      )}
                      {isEmptyRow && <div className="h-9 w-9" />}
                    </div>
                  );
                })}
              </div>
            </div>
          </TabsContent>

          {/* Variables Tab */}
          <TabsContent
            value="variables"
            className="flex-1 overflow-auto px-6 py-4 space-y-4 mt-0"
          >
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-medium">Environment Variables</h3>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Associate secrets and variables configured on the Secrets
                    page
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2 pb-2 border-b border-border">
                <span className="text-xs text-muted-foreground mr-1">
                  Environments:
                </span>
                <ToggleGroup
                  multiple
                  value={selectedEnvironments}
                  onValueChange={(value) => {
                    if (value.length > 0) {
                      setSelectedEnvironments(value as Environment[]);
                    }
                  }}
                  className="gap-1"
                >
                  <ToggleGroupItem value="development" className="h-7 text-xs">
                    Development
                  </ToggleGroupItem>
                  <ToggleGroupItem value="staging" className="h-7 text-xs">
                    Staging
                  </ToggleGroupItem>
                  <ToggleGroupItem value="production" className="h-7 text-xs">
                    Production
                  </ToggleGroupItem>
                </ToggleGroup>
                {selectedEnvironments.length > 1 && (
                  <span className="text-xs text-muted-foreground">
                    (showing common variables)
                  </span>
                )}
              </div>

              <div className="space-y-2">
                {getFilteredVariablesForEnvironments().map(
                  (variable, index) => {
                    const secret = getSecretById(variable.secretId);
                    if (!secret) return null;

                    return (
                      <div
                        key={variable.secretId}
                        className="flex items-start gap-3 p-3 bg-muted/30 rounded-md border border-border group"
                      >
                        <div className="flex-shrink-0 mt-0.5">
                          {secret.type === "secret" ? (
                            <Lock className="h-4 w-4 text-orange-500" />
                          ) : (
                            <Variable className="h-4 w-4 text-blue-500" />
                          )}
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-baseline gap-2 mb-0.5">
                            <span className="font-mono text-sm font-medium">
                              {secret.name}
                            </span>
                            {secret.type === "variable" && secret.value && (
                              <>
                                <span className="text-muted-foreground text-xs">
                                  =
                                </span>
                                <span className="text-xs text-muted-foreground font-mono truncate">
                                  {secret.value}
                                </span>
                              </>
                            )}
                          </div>
                          <div className="text-xs text-muted-foreground">
                            {formatEnvironments(variable.environments)}
                          </div>
                        </div>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => {
                            const index = variableConfigs.findIndex(
                              (v) => v.secretId === variable.secretId,
                            );
                            if (index !== -1) removeVariable(index);
                          }}
                          className="h-8 w-8 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground hover:text-destructive"
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    );
                  },
                )}

                <div className="flex items-start gap-2">
                  <div className="flex-1 relative">
                    <div className="relative">
                      <Input
                        value={variableNameInput[variableConfigs.length] ?? ""}
                        onChange={(e) => {
                          const name = e.target.value;
                          const secret = availableSecrets.find(
                            (s) => s.name === name,
                          );
                          if (secret) {
                            setVariableConfigs([
                              ...variableConfigs,
                              {
                                secretId: secret.id,
                                environments: selectedEnvironments,
                              },
                            ]);
                            setVariableNameInput({});
                          } else {
                            setVariableNameInput({
                              ...variableNameInput,
                              [variableConfigs.length]: name,
                            });
                          }
                        }}
                        onFocus={() =>
                          setShowVariableSuggestions(variableConfigs.length)
                        }
                        onBlur={() =>
                          setTimeout(
                            () => setShowVariableSuggestions(null),
                            200,
                          )
                        }
                        placeholder={
                          selectedEnvironments.length > 1
                            ? `Add to ${selectedEnvironments.length} environments...`
                            : "Add variable..."
                        }
                        className="h-9 text-sm font-mono pr-8"
                      />
                      <Button
                        variant="ghost"
                        size="icon"
                        className="absolute right-0 top-0 h-9 w-8 text-muted-foreground hover:text-foreground"
                        onClick={() =>
                          setShowVariableSuggestions(
                            showVariableSuggestions === variableConfigs.length
                              ? null
                              : variableConfigs.length,
                          )
                        }
                      >
                        <ChevronDown className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                    {showVariableSuggestions === variableConfigs.length && (
                      <div className="absolute top-full left-0 right-0 mt-1 bg-popover border border-border rounded-md shadow-lg z-10 max-h-48 overflow-auto">
                        {getFilteredVariables(variableConfigs.length).map(
                          (availableSecret) => (
                            <button
                              key={availableSecret.id}
                              onClick={() => {
                                setVariableConfigs([
                                  ...variableConfigs,
                                  {
                                    secretId: availableSecret.id,
                                    environments: selectedEnvironments,
                                  },
                                ]);
                                setVariableNameInput({});
                                setShowVariableSuggestions(null);
                              }}
                              className="w-full px-3 py-2 text-left hover:bg-accent text-sm flex flex-col gap-1"
                            >
                              <div className="flex items-center justify-between gap-2">
                                <span className="font-medium font-mono">
                                  {availableSecret.name}
                                </span>
                                <Badge
                                  variant="outline"
                                  className={`text-xs border-0 ${
                                    availableSecret.type === "secret"
                                      ? "bg-orange-500/20 text-orange-600 dark:text-orange-400"
                                      : "bg-blue-500/20 text-blue-600 dark:text-blue-400"
                                  }`}
                                >
                                  {availableSecret.type}
                                </Badge>
                              </div>
                              {availableSecret.type === "variable" &&
                                availableSecret.value && (
                                  <span className="text-xs text-muted-foreground font-mono truncate">
                                    {availableSecret.value}
                                  </span>
                                )}
                            </button>
                          ),
                        )}
                        {getFilteredVariables(variableConfigs.length).length ===
                          0 && (
                          <div className="px-3 py-2 text-sm text-muted-foreground">
                            No available variables
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                  <div className="h-9 w-9" />
                </div>
              </div>
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </>
  );
}
