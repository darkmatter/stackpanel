"use client";

import { Link, useCanGoBack, useNavigate, useRouter, useRouterState } from "@tanstack/react-router";
import { Avatar, AvatarFallback } from "@ui/avatar";
import { Button } from "@ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@ui/dropdown-menu";
import { Input } from "@ui/input";
import { ArrowLeft, Bell, LogOut, Search, Settings, User } from "lucide-react";
import { AgentStatus } from "@/components/agent-connect";
import { ShellStatus } from "./shell-status";
import { AgentConsoleDialog } from "./agent-console-dialog";
import type { PanelType } from "./dashboard-sidebar";
import { SidebarTrigger } from "../ui/sidebar";

const panelTitles: Record<PanelType, string> = {
  overview: "Overview",
  dashboard: "Dashboard",
  setup: "Setup",
  services: "Services",
  databases: "Databases",
  secrets: "Secrets",
  devshells: "Dev Shells",
  packages: "Packages",
  team: "Team",
  apps: "Apps",
  tasks: "Tasks",
  processes: "Process Compose",
  variables: "Variables",
  configuration: "Configuration",
  "local-config": "Local Config",
  network: "Network",
  extensions: "Extensions",
  modules: "Modules",
  files: "Generated Files",
  terminal: "Terminal",
  roadmap: "Roadmap",
  infra: "Infrastructure",
  deploy: "Deploy",
  inspector: "Inspector",
};

const pathToPanelMap: Record<string, PanelType> = {
  "/studio": "overview",
  "/studio/": "overview",
  "/studio/dashboard": "dashboard",
  "/studio/setup": "setup",
  "/studio/apps": "apps",
  "/studio/tasks": "tasks",
  "/studio/processes": "processes",
  "/studio/variables": "variables",
  "/studio/configuration": "configuration",
  "/studio/local-config": "local-config",
  "/studio/services": "services",
  "/studio/databases": "databases",
  "/studio/secrets": "secrets",
  "/studio/devshells": "devshells",
  "/studio/packages": "packages",
  "/studio/team": "team",
  "/studio/network": "network",
  "/studio/extensions": "extensions",
  "/studio/modules": "modules",
  "/studio/files": "files",
  "/studio/terminal": "terminal",
  "/studio/roadmap": "roadmap",
  "/studio/deploy": "deploy",
  "/studio/inspector": "inspector",
};

export function DashboardHeader() {
  const router = useRouter();
  const canGoBack = useCanGoBack();
  const routerState = useRouterState();
  const pathname = routerState.location.pathname;

  return (
    <header className="flex h-16 items-center justify-between  px-6 w-full">
      <div className="flex items-center gap-4">
        <SidebarTrigger />
        {/* <Button
          onClick={() => canGoBack ? router.history.back() : router.navigate({ to: "/studio", replace: true, search: {} })}
          className="gap-2 text-muted-foreground hover:text-foreground"
          size="sm"
          variant="ghost"
        >
          <ArrowLeft className="h-4 w-4" />
        </Button> */}
        {/* <div className="h-6 w-px bg-border" /> */}
        {/* <h1 className="font-semibold text-foreground text-lg">
          {panelTitles[activePanel]}
        </h1> */}
      </div>

      <div className="flex items-center gap-4">
        {/* <div className="relative">
          <Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
          <Input className="w-64 bg-secondary pl-9" placeholder="Search..." />
        </div> */}

        <div className="flex items-center gap-1">
          <AgentConsoleDialog />
          <Button
            className="text-muted-foreground hover:text-foreground"
            size="icon"
            variant="ghost"
          >
            <Bell className="h-5 w-5" />
          </Button>
          <Button
            className="text-muted-foreground hover:text-foreground"
            size="icon"
            variant="ghost"
          >
            <Settings className="h-5 w-5" />
          </Button>
        </div>

        <div className="flex items-center gap-3 rounded-lg border border-border bg-secondary/50 px-3 py-1.5 ml-auto">
          <ShellStatus />
          <div className="h-4 w-px bg-border" />
          <AgentStatus />
        </div>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button className="rounded-full" size="icon" variant="ghost">
              <Avatar className="h-8 w-8">
                <AvatarFallback className="bg-accent text-accent-foreground text-sm">
                  JD
                </AvatarFallback>
              </Avatar>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            <DropdownMenuItem>
              <User className="mr-2 h-4 w-4" />
              Profile
            </DropdownMenuItem>
            <DropdownMenuItem>
              <Settings className="mr-2 h-4 w-4" />
              Settings
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem className="text-destructive">
              <LogOut className="mr-2 h-4 w-4" />
              Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
