"use client";

import { Logo } from "@stackpanel/ui-core/logo";
import { Link, useRouterState } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import {
	Sidebar,
	SidebarContent,
	SidebarFooter,
	SidebarGroup,
	SidebarGroupContent,
	SidebarGroupLabel,
	SidebarHeader,
	SidebarMenu,
	SidebarMenuButton,
	SidebarMenuItem,
	SidebarRail,
	useSidebar,
} from "@ui/sidebar";
import {
	AppWindow,
	BookOpen,
	FileCode,
	Home,
	Network,
	Server,
	Variable,
} from "lucide-react";
import { cn } from "@/lib/utils";

type DemoNavItem = {
	id: string;
	label: string;
	icon: React.ElementType;
	to: string;
	badge?: string;
};

const overviewItems: DemoNavItem[] = [
	{ id: "overview", label: "Overview", icon: Home, to: "/demo" },
];

const mainItems: DemoNavItem[] = [
	{ id: "apps", label: "Apps", icon: AppWindow, to: "/demo/apps", badge: "4" },
	{
		id: "services",
		label: "Services",
		icon: Server,
		to: "/demo/services",
		badge: "6",
	},
	{
		id: "variables",
		label: "Variables / Secrets",
		icon: Variable,
		to: "/demo/variables",
	},
	{ id: "network", label: "Network", icon: Network, to: "/demo/network" },
	{ id: "files", label: "Generated files", icon: FileCode, to: "/demo/files" },
];

function NavItem({ item }: { item: DemoNavItem }) {
	const routerState = useRouterState();
	const pathname = routerState.location.pathname;
	const { state } = useSidebar();
	const isCollapsed = state === "collapsed";

	const isActive =
		item.to === "/demo"
			? pathname === "/demo" || pathname === "/demo/"
			: pathname === item.to || pathname.startsWith(`${item.to}/`);

	const Icon = item.icon;

	return (
		<SidebarMenuItem>
			<Link to={item.to}>
				<SidebarMenuButton
					isActive={isActive}
					tooltip={isCollapsed ? item.label : undefined}
					className={cn("rounded-lg text-sm")}
				>
					<Icon className="size-3 text-sidebar-foreground" />
					<span className="flex-1">{item.label}</span>
					{item.badge && !isCollapsed ? (
						<Badge
							variant="outline"
							className="border-border/60 px-1.5 py-0 text-[10px] text-muted-foreground"
						>
							{item.badge}
						</Badge>
					) : null}
				</SidebarMenuButton>
			</Link>
		</SidebarMenuItem>
	);
}

export function DemoSidebar() {
	const { state } = useSidebar();
	const isCollapsed = state === "collapsed";

	return (
		<Sidebar collapsible="icon">
			<SidebarHeader className="border-b border-sidebar-border px-3 py-3">
				<Link to="/" className="flex items-center gap-2">
					<Logo className="max-w-28" />
					{!isCollapsed && (
						<Badge
							variant="outline"
							className="border-amber-500/40 bg-amber-500/10 px-1.5 py-0 text-[10px] text-amber-200"
						>
							DEMO
						</Badge>
					)}
				</Link>
			</SidebarHeader>

			<SidebarContent>
				<SidebarGroup>
					<SidebarGroupContent>
						<SidebarMenu>
							{overviewItems.map((item) => (
								<NavItem key={item.id} item={item} />
							))}
						</SidebarMenu>
					</SidebarGroupContent>
				</SidebarGroup>

				<SidebarGroup>
					<SidebarGroupLabel>Manage</SidebarGroupLabel>
					<SidebarGroupContent>
						<SidebarMenu>
							{mainItems.map((item) => (
								<NavItem key={item.id} item={item} />
							))}
						</SidebarMenu>
					</SidebarGroupContent>
				</SidebarGroup>
			</SidebarContent>

			<SidebarFooter className="border-t border-sidebar-border px-3 py-3">
				<SidebarMenu>
					<SidebarMenuItem>
						<a
							href="/docs"
							className="flex items-center gap-2 rounded-md px-2 py-1.5 text-xs text-muted-foreground hover:bg-sidebar-accent hover:text-foreground"
						>
							<BookOpen className="h-3 w-3" />
							{!isCollapsed && <span>Read the docs</span>}
						</a>
					</SidebarMenuItem>
				</SidebarMenu>
			</SidebarFooter>

			<SidebarRail />
		</Sidebar>
	);
}
