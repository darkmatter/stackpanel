"use client";

import { useState } from "react";
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
    <CardContent className="border-t border-border min-h-70 animate-collapsible-down">
      {/* Horizontal tab bar */}
      <div className="flex items-center gap-1 -mx-6 px-4 pt-1 border-b border-border bg-background/70">
        {navItems.map((item) => {
          const isActive = activeSection === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => setActiveSection(item.id)}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs transition-colors relative ${
                isActive
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
        {activeSection === "docker" && <DockerTab />}
        {activeSection === "deployment" && <DeploymentTab />}
        {activeSection === "checks" && <ChecksTab />}
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
// Docker Tab (placeholder)
// ---------------------------------------------------------------------------

function DockerTab() {
  return (
    <div className="space-y-3">
      <button
        type="button"
        className="w-full flex items-center justify-center gap-1.5 px-3 py-8 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-sm text-muted-foreground"
      >
        <Plus className="h-4 w-4" />
        Configure Docker
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Deployment Tab (placeholder)
// ---------------------------------------------------------------------------

function DeploymentTab() {
  return (
    <div className="space-y-3">
      <button
        type="button"
        className="w-full flex items-center justify-center gap-1.5 px-3 py-8 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-sm text-muted-foreground"
      >
        <Plus className="h-4 w-4" />
        Configure Deployment
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Checks Tab (placeholder)
// ---------------------------------------------------------------------------

function ChecksTab() {
  return (
    <div className="space-y-3">
      <button
        type="button"
        className="w-full flex items-center justify-center gap-1.5 px-3 py-8 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-sm text-muted-foreground"
      >
        <Plus className="h-4 w-4" />
        Add check
      </button>
    </div>
  );
}
