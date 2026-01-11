import { Outlet, createFileRoute, useLocation } from "@tanstack/react-router";
import { useState } from "react";
import { DashboardHeader } from "@/components/studio/dashboard-header";
import { DashboardSidebar } from "@/components/studio/dashboard-sidebar";
import { AgentSSEProvider } from "@/lib/agent-sse-provider";
import { AgentProvider, useAgentContext } from "@/lib/agent-provider";
import { AgentConnect } from "@/components/agent-connect";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/studio")({
  component: StudioLayout,
});

function StudioLayout() {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  return (
    <AgentProvider>
      <AgentSSEProvider>
        <div className="studio flex h-screen bg-background">
          <DashboardSidebar
            collapsed={sidebarCollapsed}
            onToggleCollapse={() => setSidebarCollapsed(!sidebarCollapsed)}
          />
          <div className="flex flex-1 flex-col overflow-hidden">
            <DashboardHeader />
            <EnsureAgent />
          </div>
        </div>
      </AgentSSEProvider>
    </AgentProvider>
  );
}

function EnsureAgent() {
  const { isConnected } = useAgentContext();
  const location = useLocation();
  const isOverview = location.pathname === "/studio";
  return (
    <div>
      <div
        className={cn(
          "duration-300 ease-in-out z-10 m-6 ",
          isConnected &&
            !isOverview &&
            "animate-out slide-out-to-top fade-out hidden",
          !isConnected && !isOverview && "animate-in slide-in-from-top fade-in",
        )}
      >
        <AgentConnect />
      </div>
      <main
        className={cn(
          "flex-1 overflow-auto p-6",
          isConnected
            ? "animate-in blur-in"
            : "animate-out blur-out blur-sm -mt-32 opacity-50 z-0 pointer-events-none",
        )}
      >
        <Outlet />
      </main>
    </div>
  );
}
