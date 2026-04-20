import { createFileRoute, Outlet, useLocation } from "@tanstack/react-router";
import { useMemo } from "react";
import { AgentConnect } from "@/components/agent-connect";
import { DashboardHeader } from "@/components/studio/dashboard-header";
import { DashboardSidebar } from "@/components/studio/dashboard-sidebar";
import {
  SidebarInset,
  SidebarProvider,
} from "@/components/ui/sidebar";
import { AgentProvider, useAgentContext } from "@/lib/agent-provider";
import { AgentSSEProvider } from "@/lib/agent-sse-provider";
import { useAgentLiveQuerySync } from "@/lib/use-agent";
import { ProjectProvider } from "@/lib/project-provider";
import { cn } from "@/lib/utils";
import { FeatureFlagProvider } from "@gen/featureflags";

// Search params for optional project selection
interface StudioSearchParams {
  project?: string;
}

function getStudioAgentConfig() {
  const host = import.meta.env.VITE_STACKPANEL_AGENT_HOST || "localhost";
  const parsedPort = Number.parseInt(
    import.meta.env.VITE_STACKPANEL_AGENT_PORT || "",
    10,
  );
  const token = import.meta.env.VITE_STACKPANEL_AGENT_TOKEN || undefined;

  return {
    host,
    port: Number.isFinite(parsedPort) ? parsedPort : 9876,
    token,
  };
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
  const { host, port, token } = getStudioAgentConfig();

  return (
    // SSE provider is outside so AgentProvider can consume SSE status for health
    <AgentSSEProvider host={host} port={port} token={token}>
      <AgentProvider host={host} port={port} token={token}>
        <AgentQuerySync />
        <ProjectProvider initialProjectId={project}>
          <FeatureFlagProvider>
            <SidebarProvider>
              <DashboardSidebar />
              {/* <SidebarTrigger /> */}
              <SidebarInset>
                <DashboardHeader />
                <EnsureAgent />
              </SidebarInset>
            </SidebarProvider>
          </FeatureFlagProvider>
        </ProjectProvider>
      </AgentProvider>
    </AgentSSEProvider>
  );
}

function AgentQuerySync() {
  useAgentLiveQuerySync();
  return null;
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
