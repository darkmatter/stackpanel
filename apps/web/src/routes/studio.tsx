import { createFileRoute, Outlet, useLocation } from "@tanstack/react-router";
import { useMemo } from "react";
import { AgentConnect } from "@/components/agent-connect";
import { DashboardHeader } from "@/components/studio/dashboard-header";
import { DashboardSidebar } from "@/components/studio/dashboard-sidebar";
import {
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { AgentProvider, useAgentContext } from "@/lib/agent-provider";
import { AgentSSEProvider } from "@/lib/agent-sse-provider";
import { ProjectProvider } from "@/lib/project-provider";
import { cn } from "@/lib/utils";

// Search params for optional project selection
interface StudioSearchParams {
  project?: string;
}

export const Route = createFileRoute("/studio")({
  component: StudioLayout,
  validateSearch: (search: Record<string, unknown>): StudioSearchParams => {
    return {
      project: typeof search.project === "string" ? search.project : undefined,
    };
  },
});

function StudioLayout() {
  const { project } = Route.useSearch();

  return (
    <AgentProvider>
      <AgentSSEProvider>
        <ProjectProvider initialProjectId={project}>
          <SidebarProvider>
            <DashboardSidebar />
            {/* <SidebarTrigger /> */}
            <SidebarInset>
              <DashboardHeader />
              <EnsureAgent />
            </SidebarInset>
          </SidebarProvider>
        </ProjectProvider>
      </AgentSSEProvider>
    </AgentProvider>
  );
}

function EnsureAgent() {
  const { isConnected } = useAgentContext();
  const location = useLocation();
  const isOverview = location.pathname === "/studio";
  const isSetup = location.pathname === "/studio/setup";

  const isAgentVisible = useMemo(() => {
    if (isSetup) return !isConnected;
    return !isConnected;
  }, [isSetup, isConnected]);

  const isOverlayVisible = useMemo(() => {
    if (isOverview) return false;
    if (isSetup) return false;
    return !isConnected;
  }, [isSetup, isConnected, isOverview]);

  return (
    <div className="flex flex-1 flex-col min-h-0 max-w-7xl studio">
      <div
        className={cn(
          "duration-300 ease-in-out z-10 mx-6 my-6",
          !isAgentVisible && "animate-out slide-out-to-top fade-out hidden",
          isAgentVisible && "animate-in slide-in-from-top fade-in",
        )}
      >
        <AgentConnect overlay />
      </div>
      <main
        className={cn(
          "flex-1 overflow-auto px-6 py-4 min-h-0",
          !isOverlayVisible
            ? "animate-in blur-in"
            : "animate-out blur-out blur-sm -mt-32 opacity-50 z-0 pointer-events-none",
        )}
      >
        <Outlet />
      </main>
    </div>
  );
}
