"use client";

import {
	ChevronLeft,
	ChevronRight,
	Database,
	KeyRound,
	Layers,
	LayoutDashboard,
	Network,
	Server,
	SquareTerminal,
	Terminal,
	Users,
} from "lucide-react";
import type React from "react";
import { Button } from "@/components/ui/button";
import {
	Tooltip,
	TooltipContent,
	TooltipProvider,
	TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import type { PanelType } from "./dashboard-shell";

interface DashboardSidebarProps {
	activePanel: PanelType;
	onPanelChange: (panel: PanelType) => void;
	collapsed: boolean;
	onToggleCollapse: () => void;
}

const navItems: { id: PanelType; label: string; icon: React.ElementType }[] = [
	{ id: "overview", label: "Overview", icon: LayoutDashboard },
	{ id: "services", label: "Services", icon: Server },
	{ id: "databases", label: "Databases", icon: Database },
	{ id: "secrets", label: "Secrets", icon: KeyRound },
	{ id: "devshells", label: "Dev Shells", icon: Terminal },
	{ id: "team", label: "Team", icon: Users },
	{ id: "network", label: "Network", icon: Network },
	{ id: "terminal", label: "Terminal", icon: SquareTerminal },
];

export function DashboardSidebar({
	activePanel,
	onPanelChange,
	collapsed,
	onToggleCollapse,
}: DashboardSidebarProps) {
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
						<div className="flex items-center gap-2">
							<div className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent">
								<Layers className="h-4 w-4 text-accent-foreground" />
							</div>
							<div>
								<p className="font-semibold text-sidebar-foreground text-sm">
									StackPanel
								</p>
								<p className="text-muted-foreground text-xs">acme-corp</p>
							</div>
						</div>
					)}
					{collapsed && (
						<div className="mx-auto flex h-8 w-8 items-center justify-center rounded-lg bg-accent">
							<Layers className="h-4 w-4 text-accent-foreground" />
						</div>
					)}
				</div>

				<nav className="flex-1 space-y-1 p-2">
					{navItems.map((item) => {
						const Icon = item.icon;
						const isActive = activePanel === item.id;

						const button = (
							<button
								className={cn(
									"flex w-full items-center gap-3 rounded-lg px-3 py-2.5 font-medium text-sm transition-colors",
									isActive
										? "bg-sidebar-accent text-sidebar-accent-foreground"
										: "text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground",
								)}
								key={item.id}
								onClick={() => onPanelChange(item.id)}
							>
								<Icon
									className={cn("h-5 w-5 shrink-0", isActive && "text-accent")}
								/>
								{!collapsed && <span>{item.label}</span>}
							</button>
						);

						if (collapsed) {
							return (
								<Tooltip key={item.id}>
									<TooltipTrigger asChild>{button}</TooltipTrigger>
									<TooltipContent side="right">{item.label}</TooltipContent>
								</Tooltip>
							);
						}

						return button;
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
