"use client";

import { Logo } from "@stackpanel/ui-core/logo";
import { Link, useRouterState, useSearch } from "@tanstack/react-router";
import { Badge } from "@ui/badge";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@ui/collapsible";
import { CircularProgress } from "@ui/circular-progress";
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
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
  SidebarRail,
  useSidebar,
} from "@ui/sidebar";
import {
  Activity,
  AlertTriangle,
  AppWindow,
  BookOpen,
  CheckCircle2,
  ChevronRight,
  ChevronUp,
  FileCode,
  Home,
  Map as MapIcon,
  Network,
  Package,
  Play,
  Puzzle,
  Rocket,
  Search,
  SlidersHorizontal,
  Server,
  Settings,
  SquareTerminal,
  Terminal,
  User2,
  Users,
  Variable,
} from "lucide-react";
import type React from "react";
import { useSetupProgress } from "@/lib/use-setup-progress";
import { cn } from "@/lib/utils";
import { ProjectSelector } from "../project-selector";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@ui/dropdown-menu";
import {
  getConfigurationSections,
  type ConfigurationSection,
} from "./panels/configuration/sections";
import { useSopsConfigStatus } from "./panels/variables/use-sops-config-status";
import { getModuleIconByName } from "./panels/shared/module-icons";
import { studioPanelKey, useStudioPanels } from "./panels/shared/use-studio-panels";
import { getSetupPanelSteps } from "./panels/setup/panel-steps";

export type PanelType =
  | "overview"
  | "setup"
  | "apps"
  | "packages"
  | "tasks"
  | "processes"
  | "variables"
  | "configuration"
  | "local-config"
  | "devshells"
  | "team"
  | "network"
  | "infra"
  | "deploy"
  | "modules"
  | "panels"
  | "files"
  | "terminal"
  | "services"
  | "inspector"
  | "feature-flags"
  | "roadmap";

interface NavItem {
  id: string;
  label: string;
  icon: React.ElementType;
  special?: boolean;
}

const navItems: NavItem[] = [
  { id: "overview", label: "Overview", icon: Home },
  { id: "checks", label: "Checks", icon: Activity },
];

const mainNavItems: NavItem[] = [
  // Configuration has its own expandable menu item
  { id: "variables", label: "Variables / Secrets", icon: Variable },
  { id: "apps", label: "Apps", icon: AppWindow },
  { id: "packages", label: "Packages", icon: Package },
  { id: "processes", label: "Processes", icon: Server },
  { id: "network", label: "Network", icon: Network },
];

const toolsNavItems: NavItem[] = [
  { id: "modules", label: "Explore Modules", icon: Search },
  { id: "devshells", label: "Dev Shells", icon: Terminal },
  { id: "team", label: "Team", icon: Users },
  { id: "inspector", label: "Inspector", icon: Search },
];

const otherNavItems: NavItem[] = [
  { id: "feature-flags", label: "Feature Flags", icon: SlidersHorizontal },
  { id: "roadmap", label: "Roadmap", icon: MapIcon },
  { id: "docs", label: "Docs", icon: BookOpen },
];

const coceptsNavItems: NavItem[] = [
  { id: "tasks", label: "Tasks", icon: Play },
  { id: "services", label: "Services", icon: Server },
  // { id: "files", label: "Generated Files", icon: FileCode },
  { id: "local-config", label: "Local Config", icon: FileCode },
  { id: "terminal", label: "Terminal", icon: SquareTerminal },
];

function NavMenuItem({ item, showBadge = false }: { item: NavItem; showBadge?: boolean }) {
  const routerState = useRouterState();
  const pathname = routerState.location.pathname;
  const { state } = useSidebar();
  const isCollapsed = state === "collapsed";

  const itemPath = item.id === "overview" ? "/studio" : `/studio/${item.id}`;
  const isActive =
    item.id === "overview"
      ? pathname === "/studio" || pathname === "/studio/"
      : pathname === itemPath || pathname.startsWith(`${itemPath}/`);

  const Icon = item.icon;

  return (
    <SidebarMenuItem>
      <Link to={itemPath} search={{}}>
        <SidebarMenuButton
          isActive={isActive}
          tooltip={isCollapsed ? item.label : undefined}
          className={cn("rounded-lg text-sm")}
        >
          <Icon className="size-3 text-sidebar-foreground" />
          <span className="flex-1">{item.label}</span>
          {showBadge && !isCollapsed ? (
            <Badge variant="outline" className="px-1.5 py-0 border-amber-500/40 text-amber-600">
              <AlertTriangle className="h-3 w-3" />
            </Badge>
          ) : null}
        </SidebarMenuButton>
      </Link>
    </SidebarMenuItem>
  );
}

// Configuration section sub-item
function ConfigurationSectionItem({
  section,
  isCollapsed,
  active,
}: {
  section: ConfigurationSection;
  isCollapsed: boolean;
  active: boolean;
}) {
  const Icon = section.icon;

  return (
    <SidebarMenuSubItem>
      <SidebarMenuSubButton
        asChild
        className={cn(
          "gap-2 text-sidebar-foreground/70 text-[13px]",
          active && "bg-sidebar-accent/50 text-sidebar-accent-foreground",
        )}
      >
        <Link to="/studio/configuration" search={{ section: section.id }}>
          <Icon className="size-3" />
          {!isCollapsed && <span className="truncate">{section.label}</span>}
        </Link>
      </SidebarMenuSubButton>
    </SidebarMenuSubItem>
  );
}

// Configuration menu item with collapsible sections
function ConfigurationMenuItem() {
  const routerState = useRouterState();
  const pathname = routerState.location.pathname;
  const { section: activeSectionId } = useSearch({ strict: false });
  const { panels } = useStudioPanels();
  const sections = getConfigurationSections(panels);
  const { state } = useSidebar();
  const isCollapsed = state === "collapsed";

  const isActive =
    pathname === "/studio/configuration" || pathname.startsWith("/studio/configuration/");

  // When collapsed, just show a simple button
  if (isCollapsed) {
    return (
      <SidebarMenuItem>
        <Link to="/studio/configuration" search={{}}>
          <SidebarMenuButton isActive={isActive} tooltip="Configuration" className="rounded-lg">
            <Settings className="size-4" />
          </SidebarMenuButton>
        </Link>
      </SidebarMenuItem>
    );
  }

  return (
    <Collapsible defaultOpen={isActive} className="group/collapsible">
      <SidebarMenuItem>
        <CollapsibleTrigger asChild>
          <SidebarMenuButton isActive={isActive} className="rounded-lg">
            <Settings className="size-4" />
            <span className="flex-1">Configuration</span>
            <ChevronRight className="ml-auto size-4 transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" />
          </SidebarMenuButton>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <SidebarMenuSub>
            {sections.map((section) => (
              <ConfigurationSectionItem
                key={section.id}
                section={section}
                active={
                  isActive &&
                  (activeSectionId === section.id ||
                    (!activeSectionId && section.id === sections[0]?.id))
                }
                isCollapsed={isCollapsed}
              />
            ))}
          </SidebarMenuSub>
        </CollapsibleContent>
      </SidebarMenuItem>
    </Collapsible>
  );
}

function ModulePanelsMenuItem() {
  const routerState = useRouterState();
  const pathname = routerState.location.pathname;
  const { module: activeModuleId } = useSearch({ strict: false });
  const { state } = useSidebar();
  const isCollapsed = state === "collapsed";
  const isActive = pathname === "/studio/panels" || pathname.startsWith("/studio/panels/");
  const { panels, modules } = useStudioPanels();
  const counts = new Map<string, number>();
  for (const panel of panels) {
    if (panel.slot === "module") {
      counts.set(panel.module, (counts.get(panel.module) ?? 0) + 1);
    }
  }
  const activeModule = activeModuleId ?? counts.keys().next().value;

  // When collapsed, just show a simple button
  if (isCollapsed) {
    return (
      <SidebarMenuItem>
        <Link to="/studio/panels" search={{}}>
          <SidebarMenuButton isActive={isActive} tooltip="Panels" className="rounded-lg">
            <Puzzle className="size-4" />
          </SidebarMenuButton>
        </Link>
      </SidebarMenuItem>
    );
  }

  return (
    <Collapsible defaultOpen={isActive} className="group/collapsible">
      <SidebarMenuItem>
        <CollapsibleTrigger asChild>
          <SidebarMenuButton isActive={isActive} className="rounded-lg">
            <Puzzle className="size-4" />
            <span className="flex-1">Module panels</span>
            <ChevronRight className="ml-auto size-4 transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" />
          </SidebarMenuButton>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <SidebarMenuSub className="ml-3 mr-0 pr-0">
            {Array.from(counts, ([moduleId, count]) => {
              const mod = modules.get(moduleId)!;
              const isModActive = mod.id === activeModule;
              const Icon = getModuleIconByName(mod.icon);

              return (
                <SidebarMenuSubItem key={mod.id}>
                  <SidebarMenuSubButton
                    asChild
                    isActive={isActive && isModActive}
                    className="bg-transparent  data-active:border-l-accent data-[active=true]:border-l-2  -ml-2 pl-4 data-[active=true]:bg-secondary rounded-l-none!"
                  >
                    <Link
                      to="/studio/panels"
                      search={{ module: mod.id }}
                      className="data-[active=true]:font-semibold"
                    >
                      <Icon className="size-4" />
                      <span className="flex-1">{mod.name}</span>
                      <div className="flex items-center gap-1 ml-auto">
                        <Badge variant="secondary" className="text-[10px] px-1.5 py-0">
                          {count}
                        </Badge>
                      </div>
                    </Link>
                  </SidebarMenuSubButton>
                </SidebarMenuSubItem>
              );
            })}
          </SidebarMenuSub>
        </CollapsibleContent>
      </SidebarMenuItem>
    </Collapsible>
  );
}

// Setup menu item with collapsible steps
function SetupMenuItem() {
  const routerState = useRouterState();
  const pathname = routerState.location.pathname;
  const progress = useSetupProgress();
  const { panels } = useStudioPanels();
  const steps = getSetupPanelSteps(panels);
  const { step: activeStep } = useSearch({ strict: false });
  const { state } = useSidebar();
  const isCollapsed = state === "collapsed";

  const isActive = pathname === "/studio/setup" || pathname.startsWith("/studio/setup/");
  const isComplete = progress?.isComplete ?? false;
  const progressPercent = progress ? (progress.requiredComplete / progress.requiredTotal) * 100 : 0;

  // When collapsed, just show a simple button
  if (isCollapsed) {
    return (
      <SidebarMenuItem>
        <Link to="/studio/setup" search={{}}>
          <SidebarMenuButton
            isActive={isActive}
            tooltip="Setup"
            className={cn(
              "rounded-lg",
              !isComplete && "bg-amber-500/10 text-amber-600 dark:text-amber-400",
              isComplete && "text-accent dark:text-accent",
            )}
          >
            {isComplete ? (
              <CheckCircle2 className="size-4 text-accent" />
            ) : (
              <Rocket className="size-4" />
            )}
          </SidebarMenuButton>
        </Link>
      </SidebarMenuItem>
    );
  }

  return (
    <Collapsible defaultOpen={!isComplete} className="group/collapsible">
      <SidebarMenuItem>
        <CollapsibleTrigger asChild>
          <Link to="/studio/setup" search={{}}>
            <SidebarMenuButton
              isActive={isActive}
              className={cn(
                "rounded-lg ",
                !isComplete &&
                  !isActive &&
                  "bg-sidebar-accent/10 text-sidebar-accent-foreground dark:text-sidebar-accent-foreground hover:bg-sidebar-accent/20",
                isComplete && !isActive && "text-accent dark:text-accent-foreground",
              )}
            >
              {isComplete ? (
                <CheckCircle2 className="size-4 text-accent" />
              ) : (
                <Rocket className="size-4" />
              )}
              <span className="flex-1">Setup</span>
              {!isComplete && (
                <CircularProgress
                  value={progressPercent}
                  size={24}
                  strokeWidth={2.5}
                  label={`${progress?.requiredComplete}/${progress?.requiredTotal}`}
                  indicatorClassName="stroke-amber-500"
                  trackClassName="stroke-amber-500/20"
                />
              )}
              {/*<ChevronRight className="ml-auto size-4 transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" />*/}
            </SidebarMenuButton>
          </Link>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <SidebarMenuSub>
            {steps.map((step) => (
              <SidebarMenuSubItem key={step.id}>
                <SidebarMenuSubButton asChild isActive={isActive && activeStep === step.id}>
                  <Link to="/studio/setup" search={{ step: step.id }}>
                    <step.icon className="size-3" />
                    {step.label}
                  </Link>
                </SidebarMenuSubButton>
              </SidebarMenuSubItem>
            ))}
          </SidebarMenuSub>
        </CollapsibleContent>
      </SidebarMenuItem>
    </Collapsible>
  );
}

function SidebarSlotItems({ section }: { section: string }) {
  const { panels, modules } = useStudioPanels();
  return panels
    .filter((p) => p.slot === "sidebar" && p.nav?.section === section)
    .map((panel) => {
      const label = panel.nav?.label ?? panel.title;
      const Icon = getModuleIconByName(
        panel.nav?.icon ?? modules.get(panel.module)?.icon ?? panel.icon,
      );
      return (
        <SidebarMenuItem key={studioPanelKey(panel)}>
          <SidebarMenuButton asChild tooltip={label}>
            <Link
              to="/studio/m/$moduleId"
              params={{ moduleId: panel.module }}
              hash={panel.id}
              activeOptions={{ includeHash: true }}
              activeProps={{ className: "bg-sidebar-accent text-sidebar-accent-foreground" }}
            >
              <Icon className="size-4" />
              <span>{label}</span>
            </Link>
          </SidebarMenuButton>
        </SidebarMenuItem>
      );
    });
}

export function DashboardSidebar() {
  const { state } = useSidebar();
  const isCollapsed = state === "collapsed";
  const sopsConfigStatus = useSopsConfigStatus();
  const { panels } = useStudioPanels();

  return (
    <Sidebar collapsible="icon">
      {/* Header with logo */}
      <SidebarHeader className="border-b border-sidebar-border">
        <div className="flex h-12 items-center justify-center">
          {!isCollapsed ? (
            <Link to="/studio" className="flex items-center gap-2 justify-center relative">
              <Logo className="h-6 w-auto fill-sidebar-foreground" />
              <Badge className="bg-emerald-300/10 text-slate-950-600 dark:text-slate-300 font-bold border-slate-500/30 text-[9px] px-1.5 py-0 absolute -bottom-3 -right-1">
                Beta
              </Badge>
            </Link>
          ) : (
            <Link
              to="/studio"
              className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent relative"
            >
              <span className="font-bold text-accent-foreground text-sm">S</span>
              <span className="absolute -top-1 -right-1 h-2 w-2 rounded-full bg-amber-500" />
            </Link>
          )}
        </div>
      </SidebarHeader>

      {/* Project Selector - only when expanded */}
      {!isCollapsed && (
        <div className="border-b border-sidebar-border px-3 py-3">
          <ProjectSelector variant="sidebar" />
        </div>
      )}

      {/* Main Navigation */}
      <SidebarContent>
        {/* Overview & Setup */}
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              {navItems.map((item) => (
                <NavMenuItem key={item.id} item={item} />
              ))}
              <SetupMenuItem />
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        {/* Main Features */}
        <SidebarGroup>
          <SidebarGroupLabel>Core</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {mainNavItems.map((item) => (
                <NavMenuItem
                  key={item.id}
                  item={item}
                  showBadge={item.id === "variables" && sopsConfigStatus.needsAttention}
                />
              ))}
              <ModulePanelsMenuItem />
              <SidebarSlotItems section="Core" />
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        {/* Tools */}
        <SidebarGroup>
          <SidebarGroupLabel>Workspace</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {toolsNavItems.map((item) => (
                <NavMenuItem key={item.id} item={item} />
              ))}
              <SidebarSlotItems section="Workspace" />
            </SidebarMenu>
            <ConfigurationMenuItem />
          </SidebarGroupContent>
        </SidebarGroup>

        {(["Cloud", "Extensions"] as const).map(
          (section) =>
            panels.some(
              (panel) =>
                panel.slot === "sidebar" && panel.nav?.section === section,
            ) && (
              <SidebarGroup key={section}>
                <SidebarGroupLabel>{section}</SidebarGroupLabel>
                <SidebarGroupContent>
                  <SidebarMenu>
                    <SidebarSlotItems section={section} />
                  </SidebarMenu>
                </SidebarGroupContent>
              </SidebarGroup>
            ),
        )}

        {/* Other */}
        <SidebarGroup>
          <SidebarGroupLabel>Other</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {otherNavItems.map((item) => (
                <NavMenuItem key={item.id} item={item} />
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        {/* Other */}
        <SidebarGroup>
          <SidebarGroupLabel>Coming Soon</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {coceptsNavItems.map((item) => (
                <NavMenuItem key={item.id} item={item} />
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      {/* Footer */}
      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SidebarMenuButton>
                  <User2 /> Username
                  <ChevronUp className="ml-auto" />
                </SidebarMenuButton>
              </DropdownMenuTrigger>
              <DropdownMenuContent side="top" className="w-[--radix-popper-anchor-width]">
                {otherNavItems.map((item) => (
                  <DropdownMenuItem key={item.id}>
                    <Link
                      to={
                        item.id === "docs"
                          ? "/docs"
                          : item.id === "feature-flags"
                            ? "/studio/feature-flags"
                            : "/studio/roadmap"
                      }
                      className="flex items-center"
                    >
                      <item.icon className="mr-2 h-4 w-4" />
                      {item.label}
                    </Link>
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>

      {/* Rail for collapse/expand on hover */}
      <SidebarRail />
    </Sidebar>
  );
}
