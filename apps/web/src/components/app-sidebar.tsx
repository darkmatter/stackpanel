"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  FolderOpen,
  Package,
  Key,
  ListChecks,
  Variable,
  Database,
  TerminalIcon,
  Users,
  Network,
  Puzzle,
  Shell,
  FileCode,
} from "lucide-react";

const navItems = [
  { name: "Overview", href: "/overview", icon: LayoutDashboard },
  { name: "Apps", href: "/", icon: FolderOpen },
  { name: "Packages", href: "/packages", icon: Package },
  { name: "Secrets", href: "/secrets", icon: Key },
  { name: "Tasks", href: "/tasks", icon: ListChecks },
  { name: "Variables", href: "/variables", icon: Variable },
  { name: "Databases", href: "/databases", icon: Database },
  { name: "Dev Shells", href: "/dev-shells", icon: Shell },
  { name: "Team", href: "/team", icon: Users },
  { name: "Network", href: "/network", icon: Network },
  { name: "Extensions", href: "/extensions", icon: Puzzle },
  { name: "Files", href: "/files", icon: FileCode },
  { name: "Terminal", href: "/terminal", icon: TerminalIcon },
];

export function AppSidebar() {
  const pathname = usePathname();

  return (
    <aside className="w-40 border-r border-border bg-sidebar flex flex-col">
      <div className="p-4 border-b border-sidebar-border">
        <div className="flex items-center gap-2 text-sidebar-foreground">
          <FolderOpen className="h-4 w-4" />
          <span className="text-sm font-medium">stackpanel</span>
        </div>
      </div>

      <nav className="flex-1 p-2 space-y-1">
        {navItems.map((item) => {
          const isActive = pathname === item.href;
          return (
            <Link
              key={item.name}
              href={item.href}
              className={`w-full flex items-center gap-2 px-3 py-1.5 rounded-md text-sm transition-colors ${
                isActive
                  ? "bg-sidebar-accent text-sidebar-accent-foreground"
                  : "text-sidebar-foreground hover:bg-sidebar-accent/50"
              }`}
            >
              <item.icon className="h-4 w-4" />
              <span>{item.name}</span>
            </Link>
          );
        })}
      </nav>

      <div className="p-4 border-t border-sidebar-border">
        <div className="text-xs text-muted-foreground">Demo Mode</div>
      </div>
    </aside>
  );
}
