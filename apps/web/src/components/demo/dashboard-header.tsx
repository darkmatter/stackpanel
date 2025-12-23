"use client";

import { Link } from "@tanstack/react-router";
import {
  ArrowLeft,
  Bell,
  ExternalLink,
  LogOut,
  Search,
  Settings,
  User,
} from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import type { PanelType } from "./dashboard-shell";

const panelTitles: Record<PanelType, string> = {
  overview: "Overview",
  services: "Services",
  databases: "Databases",
  secrets: "Secrets",
  devshells: "Dev Shells",
  team: "Team",
  network: "Network",
  terminal: "Terminal",
};

interface DashboardHeaderProps {
  activePanel: PanelType;
}

export function DashboardHeader({ activePanel }: DashboardHeaderProps) {
  return (
    <header className="flex h-16 items-center justify-between border-border border-b bg-card px-6">
      <div className="flex items-center gap-4">
        <Link to="/">
          <Button
            className="gap-2 text-muted-foreground hover:text-foreground"
            size="sm"
            variant="ghost"
          >
            <ArrowLeft className="h-4 w-4" />
            Exit Demo
          </Button>
        </Link>
        <div className="h-6 w-px bg-border" />
        <h1 className="font-semibold text-foreground text-lg">
          {panelTitles[activePanel]}
        </h1>
      </div>

      <div className="flex items-center gap-4">
        <div className="relative">
          <Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
          <Input className="w-64 bg-secondary pl-9" placeholder="Search..." />
        </div>

        <div className="flex items-center gap-1">
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

        <div className="flex items-center gap-2 rounded-lg border border-border bg-secondary/50 px-2 py-1">
          <span className="h-2 w-2 animate-pulse rounded-full bg-accent" />
          <span className="text-muted-foreground text-xs">stackpanel.internal</span>
          <ExternalLink className="h-3 w-3 text-muted-foreground" />
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
