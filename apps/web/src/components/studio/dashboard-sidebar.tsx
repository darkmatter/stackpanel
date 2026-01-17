"use client";

import { Link, useRouterState } from "@tanstack/react-router";
import { Button } from "@ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@ui/tooltip";
import {
  AppWindow,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Database,
  FileCode,
  Layers,
  LayoutDashboard,
  Network,
  Package,
  Play,
  Puzzle,
  Rocket,
  Server,
  Settings,
  SquareTerminal,
  Terminal,
  Users,
  Variable,
} from "lucide-react";
import React, { useCallback, useEffect, useState } from "react";
import { cn } from "@/lib/utils";
import { ProjectSelector } from "../project-selector";
import { AgentHttpClient } from "@/lib/agent";
import { useAgentContext } from "@/lib/agent-provider";

interface DashboardSidebarProps {
  collapsed: boolean;
  onToggleCollapse: () => void;
}

export type PanelType =
  | "overview"
  | "setup"
  | "apps"
  | "packages"
  | "secrets"
  | "tasks"
  | "variables"
  | "configuration"
  | "databases"
  | "devshells"
  | "team"
  | "network"
  | "extensions"
  | "files"
  | "terminal"
  | "services";

const navItems: { id: string; label: string; icon: React.ElementType; special?: boolean }[] = [
  // required: maybe create onboarding flow
  { id: "overview", label: "Overview", icon: LayoutDashboard },
  { id: "setup", label: "Setup", icon: Rocket, special: true },
  { id: "divider", label: "", icon: React.Fragment },
  { id: "apps", label: "Apps", icon: AppWindow },
  { id: "packages", label: "Packages", icon: Package },
  // { id: "secrets", label: "Secrets", icon: KeyRound },
  { id: "variables", label: "Variables / Secrets", icon: Variable },
  { id: "configuration", label: "Configuration", icon: Settings },
  // rest
  { id: "tasks", label: "Tasks", icon: Play },
  { id: "divider", label: "", icon: React.Fragment },
  { id: "databases", label: "Databases", icon: Database },
  { id: "devshells", label: "Dev Shells", icon: Terminal },
  { id: "team", label: "Team", icon: Users },
  { id: "network", label: "Network", icon: Network },
  { id: "extensions", label: "Extensions", icon: Puzzle },
  { id: "files", label: "Generated Files", icon: FileCode },
  { id: "terminal", label: "Terminal", icon: SquareTerminal },
  // consider removing
  { id: "divider", label: "", icon: React.Fragment },
  { id: "services", label: "Services", icon: Server },
];

// Setup progress hook
function useSetupProgress() {
  const { token } = useAgentContext();
  const [progress, setProgress] = useState<{ complete: number; total: number } | null>(null);

  const loadProgress = useCallback(async () => {
    if (!token) return;
    try {
      const client = new AgentHttpClient("localhost", 9876, token);
      
      // Check if project was confirmed
      const projectConfirmed = localStorage.getItem("stackpanel-project-confirmed") === "true";
      
      // Check identity config
      const identity = await client.getAgeIdentity();
      const hasIdentity = identity.type !== "";
      
      // Check if .sops.yaml exists
      let hasSopsConfig = false;
      try {
        await client.readFile(".sops.yaml");
        hasSopsConfig = true;
      } catch {
        // File doesn't exist
      }
      
      // Required steps: project confirmed + identity + sops config
      const complete = (projectConfirmed ? 1 : 0) + (hasIdentity ? 1 : 0) + (hasSopsConfig ? 1 : 0);
      const total = 3;
      
      setProgress({ complete, total });
    } catch (err) {
      console.warn("Failed to load setup progress:", err);
    }
  }, [token]);

  useEffect(() => {
    loadProgress();
  }, [loadProgress]);

  return progress;
}

export function DashboardSidebar({
  collapsed,
  onToggleCollapse,
}: DashboardSidebarProps) {
  const routerState = useRouterState();
  const pathname = routerState.location.pathname;
  const setupProgress = useSetupProgress();
  const isSetupComplete = setupProgress?.complete === setupProgress?.total;
  
  return (
    <TooltipProvider delayDuration={0}>
      <aside
        className={cn(
          "flex h-full flex-col border-sidebar-border border-r bg-sidebar transition-all duration-200",
          collapsed ? "w-16" : "w-64",
        )}
      >
        <div className="flex h-16 items-center justify-between border-sidebar-border border-b px-4">
          {!collapsed && (
            <div className="w-full">
              <ProjectSelector variant="sidebar" />
            </div>
          )}
          {collapsed && (
            <div className="mx-auto flex h-8 w-8 items-center justify-center rounded-lg bg-accent">
              <Layers className="h-4 w-4 text-accent-foreground" />
            </div>
          )}
        </div>

        <nav className="flex-1 space-y-1 p-2">
          {navItems.map((item, i) => {
            const Icon = item.icon;
            // "overview" is the index route at /studio, others are at /studio/<id>
            const itemPath =
              item.id === "overview" ? "/studio" : `/studio/${item.id}`;
            const isActive =
              item.id === "overview"
                ? pathname === "/studio" || pathname === "/studio/"
                : pathname === itemPath || pathname.startsWith(`${itemPath}/`);

            // Special handling for setup item with progress
            const isSetupItem = item.id === "setup";
            const showProgressBadge = isSetupItem && setupProgress && !isSetupComplete;

            const linkContent = (
              <Link
                to={itemPath}
                activeOptions={{ exact: item.id === "overview" }}
                activeProps={{
                  className: "bg-sidebar-accent text-sidebar-accent-foreground",
                }}
                className={cn(
                  "flex w-full items-center gap-3 rounded-lg px-3 py-2.5 font-medium text-sm tracking-tight font-montserrat transition-colors",
                  isActive
                    ? "bg-sidebar-accent text-sidebar-accent-foreground"
                    : "text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
                  // Highlight setup if incomplete
                  isSetupItem && !isSetupComplete && !isActive && "bg-amber-500/10 text-amber-600 dark:text-amber-400 hover:bg-amber-500/20",
                  // Green when complete
                  isSetupItem && isSetupComplete && !isActive && "text-emerald-600 dark:text-emerald-400",
                )}
              >
                {isSetupItem && isSetupComplete ? (
                  <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" />
                ) : (
                  <Icon
                    className={cn(
                      "h-5 w-5 shrink-0",
                      isActive && "text-sidebar-accent-foreground",
                    )}
                  />
                )}
                {!collapsed && (
                  <span className="flex-1">{item.label}</span>
                )}
                {!collapsed && showProgressBadge && (
                  <span className="text-xs px-1.5 py-0.5 rounded-full bg-amber-500/20 text-amber-700 dark:text-amber-300 font-medium">
                    {setupProgress.complete}/{setupProgress.total}
                  </span>
                )}
                {!collapsed && isSetupItem && isSetupComplete && (
                  <span className="text-xs text-emerald-600">✓</span>
                )}
              </Link>
            );

            if (collapsed) {
              return (
                <Tooltip key={item.id}>
                  <TooltipTrigger asChild>{linkContent}</TooltipTrigger>
                  <TooltipContent side="right" className="flex items-center gap-2">
                    {item.label}
                    {showProgressBadge && (
                      <span className="text-xs px-1.5 py-0.5 rounded-full bg-amber-500/20 text-amber-700">
                        {setupProgress.complete}/{setupProgress.total}
                      </span>
                    )}
                  </TooltipContent>
                </Tooltip>
              );
            }

            if (item.id === "divider") {
              return (
                <div
                  key={`${item.id}-${i}`}
                  className="border-t border-sidebar-border my-2"
                />
              );
            }

            return <div key={item.id}>{linkContent}</div>;
          })}
        </nav>

        <div className="border-sidebar-border border-t p-2">
          <Button
            className="w-full justify-center text-muted-foreground hover:text-foreground"
            onClick={onToggleCollapse}
            size="sm"
            variant="ghost"
          >
            {collapsed ? (
              <ChevronRight className="h-4 w-4" />
            ) : (
              <ChevronLeft className="h-4 w-4" />
            )}
          </Button>
        </div>

        {!collapsed && (
          <div className="border-sidebar-border border-t p-4">
            <div className="rounded-lg bg-sidebar-accent/50 p-3">
              <p className="font-medium text-sidebar-foreground text-xs">
                Demo Mode
              </p>
              <p className="mt-1 text-muted-foreground text-xs">
                This is a preview of your StackPanel dashboard.
              </p>
            </div>
          </div>
        )}
      </aside>
    </TooltipProvider>
  );
}
