"use client";

import { useMemo, useState } from "react";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import {
  Boxes,
  Container,
  FolderOpen,
  ListChecks,
  Pencil,
  Plus,
  Rocket,
  Settings,
  ShieldCheck,
  Variable,
} from "lucide-react";
import { AppVariablesSection } from "./app-variables-section";
import type { DisplayVariable, TaskWithCommand } from "./types";
import type { AvailableVariable } from "./app-variables-section/types";
import { CardContent } from "@/components/ui/card";
import type { AppModulePanel, ModuleGroup } from "../shared/panel-types";
import {
  AppConfigFormRenderer,
  getModuleIconByName,
  formatModuleName,
} from "../shared";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Nav section definition */
interface NavItem {
  id: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
}

const navItems: NavItem[] = [
  { id: "overview", label: "Overview", icon: Settings },
  { id: "tasks", label: "Tasks", icon: ListChecks },
  { id: "variables", label: "Variables", icon: Variable },
  { id: "docker", label: "Docker", icon: Container },
  { id: "deployment", label: "Deployment", icon: Rocket },
  { id: "checks", label: "Checks", icon: ShieldCheck },
  { id: "modules", label: "Modules", icon: Boxes },
];

/** The currently active framework for an app, or null for none */
export type AppFramework = "go" | "bun" | null;

/** Props for the expanded content area within an app item */
export interface AppExpandedContentProps {
  app: {
    id: string;
    name: string;
    path: string;
    domain: string;
    type?: string;
    port: number;
    stablePort: number;
    description?: string;
    environments: string[];
    tasks: TaskWithCommand[];
    secrets: DisplayVariable[];
    variables: DisplayVariable[];
    isRunning: boolean;
  };
  framework: AppFramework;
  environmentOptions: string[];
  availableVariables: AvailableVariable[];
  disabled?: boolean;
  /** Module config panels for this app (PANEL_TYPE_APP_CONFIG) */
  modulePanels?: AppModulePanel[];
  /** Container config panels for this app */
  containerPanels?: AppModulePanel[];
  /** Deployment config panels for this app */
  deploymentPanels?: AppModulePanel[];
  // Task editing
  editingTask: { appId: string; taskName: string } | null;
  taskCommandOverride: string;
  onTaskEdit: (appId: string, taskName: string, command: string) => void;
  onTaskSave: () => void;
  onTaskCancel: () => void;
  onTaskCommandChange: (value: string) => void;
  // Variable mutations
  onAddVariable: (
    envKey: string,
    value: string,
    environments: string[],
  ) => void;
  onUpdateVariable: (
    oldEnvKey: string,
    newEnvKey: string,
    value: string,
    environments: string[],
  ) => void;
  onDeleteVariable: (envKey: string) => void;
  onUpdateEnvironments: (environments: string[]) => void;
  // Framework mutation
  onFrameworkChange: (framework: AppFramework) => void;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function AppExpandedContent({
  app,
  framework,
  environmentOptions,
  availableVariables,
  disabled,
  modulePanels,
  containerPanels,
  deploymentPanels,
  editingTask,
  taskCommandOverride,
  onTaskEdit,
  onTaskSave,
  onTaskCancel,
  onTaskCommandChange,
  onAddVariable,
  onUpdateVariable,
  onDeleteVariable,
  onUpdateEnvironments,
  onFrameworkChange,
}: AppExpandedContentProps) {
  const [activeSection, setActiveSection] = useState("overview");

  return (
    <CardContent className="border-t border-border min-h-70 animate-accordion-down">
      {/* Horizontal tab bar */}
      <div className="flex items-center gap-1 -mx-6 px-4 pt-1 border-b border-border bg-background/70">
        {navItems.map((item) => {
          const isActive = activeSection === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => setActiveSection(item.id)}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs transition-colors relative ${isActive
                ? "text-primary"
                : "text-muted-foreground hover:text-foreground"
                }`}
            >
              <item.icon className="h-3.5 w-3.5" />
              {item.label}
              {isActive && (
                <span className="absolute bottom-0 left-2 right-2 h-0.5 bg-primary rounded-t" />
              )}
            </button>
          );
        })}
      </div>

      {/* Content area */}
      <div className="p-4 overflow-auto">
        {activeSection === "overview" && (
          <OverviewTab
            app={app}
            framework={framework}
            disabled={disabled}
            onNavigate={setActiveSection}
            onFrameworkChange={onFrameworkChange}
          />
        )}
        {activeSection === "tasks" && (
          <TasksTab
            app={app}
            editingTask={editingTask}
            taskCommandOverride={taskCommandOverride}
            onTaskEdit={onTaskEdit}
            onTaskSave={onTaskSave}
            onTaskCancel={onTaskCancel}
            onTaskCommandChange={onTaskCommandChange}
          />
        )}
        {activeSection === "variables" && (
          <AppVariablesSection
            variables={app.variables}
            secrets={app.secrets}
            environmentOptions={environmentOptions}
            availableVariables={availableVariables}
            onAddVariable={onAddVariable}
            onUpdateVariable={onUpdateVariable}
            onDeleteVariable={onDeleteVariable}
            onUpdateEnvironments={onUpdateEnvironments}
            disabled={disabled}
          />
        )}
        {activeSection === "modules" && (
          <ModulesTab
            appId={app.id}
            panels={modulePanels ?? []}
            disabled={disabled}
          />
        )}
        {activeSection === "docker" && (
          <DockerTab
            appId={app.id}
            panels={containerPanels ?? []}
            disabled={disabled}
          />
        )}
        {activeSection === "deployment" && (
          <DeploymentTab
            appId={app.id}
            panels={deploymentPanels ?? []}
            disabled={disabled}
          />
        )}
        {activeSection === "checks" && <ChecksTab appId={app.id} />}
      </div>
    </CardContent>
  );
}

// ---------------------------------------------------------------------------
// Overview Tab
// ---------------------------------------------------------------------------

const FRAMEWORK_OPTIONS: Array<{
  value: string;
  label: string;
  description: string;
}> = [
    { value: "none", label: "None", description: "No framework module" },
    {
      value: "go",
      label: "Go",
      description: "Go toolchain, air live reload, and binary packaging",
    },
    {
      value: "bun",
      label: "Bun",
      description: "Bun runtime, build scripts, and packaging",
    },
  ];

function OverviewTab({
  app,
  framework,
  disabled,
  onNavigate,
  onFrameworkChange,
}: {
  app: AppExpandedContentProps["app"];
  framework: AppFramework;
  disabled?: boolean;
  onNavigate: (section: string) => void;
  onFrameworkChange: (framework: AppFramework) => void;
}) {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div>
          <div className="text-xs text-muted-foreground mb-1">Path</div>
          <div className="flex items-center gap-2 text-sm">
            <FolderOpen className="h-3 w-3 text-muted-foreground" />
            <span className="font-mono text-xs">{app.path}</span>
          </div>
        </div>
        {app.domain && (
          <div>
            <div className="text-xs text-muted-foreground mb-1">Domain</div>
            <div className="text-sm font-mono">{app.domain}</div>
          </div>
        )}
        <div>
          <div className="text-xs text-muted-foreground mb-1">Port</div>
          <div className="text-sm font-mono">{app.port}</div>
        </div>
        <div>
          <div className="text-xs text-muted-foreground mb-1">Framework</div>
          <Select
            value={framework ?? "none"}
            disabled={disabled}
            onValueChange={(value) =>
              onFrameworkChange(value === "none" ? null : (value as "go" | "bun"))
            }
          >
            <SelectTrigger size="sm" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {FRAMEWORK_OPTIONS.map((opt) => (
                <SelectItem key={opt.value} value={opt.value}>
                  {opt.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        {app.description && (
          <div className="col-span-2">
            <div className="text-xs text-muted-foreground mb-1">
              Description
            </div>
            <div className="text-sm">{app.description}</div>
          </div>
        )}
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-3 gap-3 pt-2">
        <button
          type="button"
          onClick={() => onNavigate("tasks")}
          className="p-3 rounded-md bg-muted/50 border border-border hover:border-primary/50 transition-colors text-left"
        >
          <div className="text-xs text-muted-foreground">Tasks</div>
          <div className="text-lg font-medium">{app.tasks.length}</div>
        </button>
        <button
          type="button"
          onClick={() => onNavigate("variables")}
          className="p-3 rounded-md bg-muted/50 border border-border hover:border-primary/50 transition-colors text-left"
        >
          <div className="text-xs text-muted-foreground">Variables</div>
          <div className="text-lg font-medium">
            {app.variables.length + app.secrets.length}
          </div>
        </button>
        <button
          type="button"
          onClick={() => onNavigate("checks")}
          className="p-3 rounded-md bg-muted/50 border border-border hover:border-primary/50 transition-colors text-left"
        >
          <div className="text-xs text-muted-foreground">Environments</div>
          <div className="text-lg font-medium">{app.environments.length}</div>
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tasks Tab
// ---------------------------------------------------------------------------

function TasksTab({
  app,
  editingTask,
  taskCommandOverride,
  onTaskEdit,
  onTaskSave,
  onTaskCancel,
  onTaskCommandChange,
}: {
  app: AppExpandedContentProps["app"];
  editingTask: { appId: string; taskName: string } | null;
  taskCommandOverride: string;
  onTaskEdit: (appId: string, taskName: string, command: string) => void;
  onTaskSave: () => void;
  onTaskCancel: () => void;
  onTaskCommandChange: (value: string) => void;
}) {
  if (app.tasks.length === 0) {
    return (
      <div className="space-y-3">
        <p className="text-xs text-muted-foreground">
          No tasks discovered. Make sure the app has a package.json with
          scripts.
        </p>
        <button
          type="button"
          className="w-full flex items-center justify-center gap-1.5 px-3 py-2 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-xs text-muted-foreground"
        >
          <Plus className="h-3 w-3" />
          Add task
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-1.5">
      {app.tasks.map((task) => {
        const isEditing =
          editingTask?.appId === app.id && editingTask?.taskName === task.name;

        return (
          <div
            key={task.name}
            className="group flex items-center gap-2 px-3 py-2 rounded-md border border-border bg-background/70 hover:bg-background/10"
          >
            <div className="h-1.5 w-1.5 rounded-full bg-green-500 shrink-0" />
            <span className="text-xs font-medium min-w-24 text-primary/80 font-mono">
              {task.name}
            </span>
            {isEditing ? (
              <div className="flex-1 flex items-center gap-2">
                <Input
                  value={taskCommandOverride}
                  onChange={(e) => onTaskCommandChange(e.target.value)}
                  className="h-7 text-xs font-mono flex-1 font-medium"
                  autoFocus
                />
                <Button size="sm" className="h-7 text-xs" onClick={onTaskSave}>
                  Save
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  className="h-7 text-xs"
                  onClick={onTaskCancel}
                >
                  Cancel
                </Button>
              </div>
            ) : (
              <>
                <span className="text-xs text-muted-foreground font-mono truncate flex-1 border-l pl-4">
                  {task.command}
                </span>
                <Pencil
                  className="h-3 w-3 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer shrink-0"
                  onClick={() => onTaskEdit(app.id, task.name, task.command)}
                />
              </>
            )}
          </div>
        );
      })}
      <button
        type="button"
        className="w-full flex items-center justify-center gap-1.5 px-3 py-2 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-xs text-muted-foreground"
      >
        <Plus className="h-3 w-3" />
        Add task
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Docker Tab - Container configuration
// ---------------------------------------------------------------------------

function DockerTab({
  appId,
  panels,
  disabled,
}: {
  appId: string;
  panels: AppModulePanel[];
  disabled?: boolean;
}) {
  if (panels.length === 0) {
    return (
      <div className="space-y-3">
        <p className="text-xs text-muted-foreground">
          Container building is not enabled for this app.
        </p>
        <p className="text-xs text-muted-foreground/70">
          Enable container support in your Nix configuration:
        </p>
        <pre className="text-xs bg-muted/50 p-3 rounded-md font-mono overflow-x-auto">
          {`stackpanel.apps.${appId}.container.enable = true;`}
        </pre>
        <button
          type="button"
          className="w-full flex items-center justify-center gap-1.5 px-3 py-4 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-sm text-muted-foreground"
        >
          <Plus className="h-4 w-4" />
          Enable Container
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {panels.map((panel) => (
        <AppConfigFormRenderer
          key={panel.id}
          panel={panel}
          appId={appId}
          disabled={disabled}
        />
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Deployment Tab - Fly.io / Cloudflare configuration
// ---------------------------------------------------------------------------

function DeploymentTab({
  appId,
  panels,
  disabled,
}: {
  appId: string;
  panels: AppModulePanel[];
  disabled?: boolean;
}) {
  if (panels.length === 0) {
    return (
      <div className="space-y-3">
        <p className="text-xs text-muted-foreground">
          Deployment is not enabled for this app.
        </p>
        <p className="text-xs text-muted-foreground/70">
          Enable deployment in your Nix configuration:
        </p>
        <pre className="text-xs bg-muted/50 p-3 rounded-md font-mono overflow-x-auto">
          {`stackpanel.apps.${appId}.deployment = {
  enable = true;
  provider = "fly"; # or "cloudflare"
};`}
        </pre>
        <button
          type="button"
          className="w-full flex items-center justify-center gap-1.5 px-3 py-4 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-sm text-muted-foreground"
        >
          <Plus className="h-4 w-4" />
          Enable Deployment
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {panels.map((panel) => (
        <AppConfigFormRenderer
          key={panel.id}
          panel={panel}
          appId={appId}
          disabled={disabled}
        />
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Checks Tab - Shows app-specific healthchecks
// ---------------------------------------------------------------------------

import { useHealthchecks } from "@/lib/healthchecks/use-healthchecks";
import { TrafficLightDot } from "@/lib/healthchecks/traffic-light";
import type { ModuleHealth, HealthcheckResult } from "@/lib/healthchecks/types";
import { RefreshCw, Activity } from "lucide-react";
import { cn } from "@/lib/utils";

function ChecksTab({ appId }: { appId: string }) {
  // Fetch all healthchecks and filter for app-related ones
  const {
    data: summary,
    isLoading,
    error,
    isRefreshing,
    runChecks,
  } = useHealthchecks({ enabled: true });

  // Filter modules relevant to this app:
  // 1. app-<appId> module (app-specific checks)
  // 2. oxlint (if app has oxlint enabled)
  // 3. Other app-related modules
  const appRelatedModules = useMemo(() => {
    if (!summary?.modules) return [];

    return Object.entries(summary.modules).filter(([moduleName, _]) => {
      // Direct app module
      if (moduleName === `app-${appId}`) return true;
      // Could extend to check if oxlint is enabled for this app, etc.
      return false;
    });
  }, [summary, appId]);

  const hasChecks = appRelatedModules.length > 0 && 
    appRelatedModules.some(([_, mod]) => mod.checks?.length > 0);

  return (
    <div className="space-y-4">
      {/* Header with run button */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Activity className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm font-medium">App Healthchecks</span>
        </div>
        <button
          type="button"
          onClick={() => runChecks(`app-${appId}`)}
          disabled={isLoading || isRefreshing}
          className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-md text-xs bg-secondary hover:bg-secondary/80 transition-colors disabled:opacity-50"
        >
          <RefreshCw
            className={cn("h-3 w-3", isRefreshing && "animate-spin")}
          />
          Run Checks
        </button>
      </div>

      {/* Error state */}
      {error && (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-400">
          {error}
        </div>
      )}

      {/* Loading state */}
      {isLoading && !summary && (
        <div className="flex items-center justify-center py-8 text-muted-foreground">
          <RefreshCw className="h-4 w-4 animate-spin mr-2" />
          Loading checks...
        </div>
      )}

      {/* No checks state */}
      {!isLoading && !hasChecks && (
        <div className="text-center py-8">
          <ShieldCheck className="h-8 w-8 mx-auto mb-3 text-muted-foreground/50" />
          <p className="text-sm text-muted-foreground mb-2">
            No healthchecks configured for this app
          </p>
          <p className="text-xs text-muted-foreground">
            Add checks in your Nix config:
          </p>
          <pre className="mt-2 p-2 rounded bg-muted text-xs text-left font-mono overflow-x-auto">
{`stackpanel.apps.${appId}.commands.check = {
  exec = "bun run typecheck";
};`}
          </pre>
        </div>
      )}

      {/* Check results */}
      {hasChecks && (
        <div className="space-y-3">
          {appRelatedModules.map(([moduleName, moduleHealth]) => (
            <AppHealthModule
              key={moduleName}
              moduleHealth={moduleHealth}
            />
          ))}
        </div>
      )}

      {/* Add check placeholder */}
      <button
        type="button"
        className="w-full flex items-center justify-center gap-1.5 px-3 py-4 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-xs text-muted-foreground"
      >
        <Plus className="h-3.5 w-3.5" />
        Add custom check
      </button>
    </div>
  );
}

function AppHealthModule({
  moduleHealth,
}: {
  moduleHealth: ModuleHealth;
}) {
  const status = moduleHealth.status || "HEALTH_STATUS_UNKNOWN";
  const checks = moduleHealth.checks || [];

  if (checks.length === 0) return null;

  return (
    <div className="rounded-lg border">
      {/* Module header */}
      <div className="flex items-center justify-between p-3 border-b bg-muted/30">
        <div className="flex items-center gap-2">
          <TrafficLightDot status={status} size="sm" />
          <span className="text-sm font-medium">{moduleHealth.displayName}</span>
          <span className="text-xs text-muted-foreground">
            {moduleHealth.healthyCount ?? 0}/{moduleHealth.totalCount ?? 0} passing
          </span>
        </div>
      </div>

      {/* Check list */}
      <div className="divide-y">
        {checks.map((result) => (
          <AppHealthcheckItem key={result.checkId} result={result} />
        ))}
      </div>
    </div>
  );
}

function AppHealthcheckItem({ result }: { result: HealthcheckResult }) {
  const check = result.check;
  const status = result.status || "HEALTH_STATUS_UNKNOWN";
  const checkName = check?.name || result.checkId;

  return (
    <div className="flex items-start gap-3 p-3">
      <div className="mt-0.5">
        <TrafficLightDot status={status} size="sm" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-sm font-medium">{checkName}</span>
          {result.durationMs > 0 && (
            <span className="text-xs text-muted-foreground">
              {result.durationMs}ms
            </span>
          )}
        </div>
        {check?.description && (
          <p className="text-xs text-muted-foreground mt-0.5">
            {check.description}
          </p>
        )}
        {result.error && (
          <p className="text-xs text-red-500 dark:text-red-400 mt-1">
            {result.error}
          </p>
        )}
        {result.output && status === "HEALTH_STATUS_HEALTHY" && (
          <p className="text-xs text-green-600 dark:text-green-400 mt-1 line-clamp-1">
            {result.output}
          </p>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Modules Tab - Vertical subnav per module + panel content
// ---------------------------------------------------------------------------

function ModulesTab({
  appId,
  panels,
  disabled,
}: {
  appId: string;
  panels: AppModulePanel[];
  disabled?: boolean;
}) {
  const [activeModule, setActiveModule] = useState<string | null>(null);

  // Group panels by module (preserves order)
  const moduleGroups: ModuleGroup[] = useMemo(() => {
    const groups: ModuleGroup[] = [];
    const seen = new Set<string>();

    for (const panel of panels) {
      if (!seen.has(panel.module)) {
        seen.add(panel.module);
        groups.push({
          id: panel.module,
          label: formatModuleName(panel.module),
          icon: panel.icon,
          panels: [],
        });
      }
      groups.find((g) => g.id === panel.module)?.panels.push(panel);
    }
    return groups;
  }, [panels]);

  // Resolve active module (default to first)
  const selected = activeModule ?? moduleGroups[0]?.id ?? null;
  const selectedGroup = moduleGroups.find((g) => g.id === selected);

  if (panels.length === 0) {
    return (
      <div className="space-y-3">
        <p className="text-xs text-muted-foreground">
          No module configuration panels available for this app.
        </p>
        <p className="text-xs text-muted-foreground">
          Module panels appear when a language module (Go, Bun, etc.) or
          tool module (OxLint, etc.) is enabled for this app.
        </p>
      </div>
    );
  }

  return (
    <div className="flex gap-4">
      {/* Vertical subnav */}
      <nav className="w-36 shrink-0 space-y-0.5 border-r border-border pr-3">
        {moduleGroups.map((group) => {
          const isActive = group.id === selected;
          const Icon = getModuleIconByName(group.icon);

          return (
            <button
              key={group.id}
              type="button"
              onClick={() => setActiveModule(group.id)}
              className={`w-full flex items-center gap-2 rounded-md px-2.5 py-1.5 text-xs transition-colors text-left ${isActive
                ? "bg-primary/10 text-primary font-medium"
                : "text-muted-foreground hover:text-foreground hover:bg-muted/50"
                }`}
            >
              <Icon className="h-3.5 w-3.5 shrink-0" />
              <span className="truncate">{group.label}</span>
            </button>
          );
        })}
      </nav>

      {/* Panel content */}
      <div className="flex-1 min-w-0 space-y-4">
        {selectedGroup?.panels.map((panel) => (
          <AppConfigFormRenderer
            key={panel.id}
            panel={panel}
            appId={appId}
            disabled={disabled}
          />
        ))}
      </div>
    </div>
  );
}
