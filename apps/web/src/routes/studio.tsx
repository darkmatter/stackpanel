import { createFileRoute, Outlet, useLocation, useNavigate } from "@tanstack/react-router";
import { useEffect, useMemo, useRef } from "react";
import { AgentConnect } from "@/components/agent-connect";
import { DemoBanner } from "@/components/demo/demo-banner";
import { DashboardHeader } from "@/components/studio/dashboard-header";
import { DashboardSidebar } from "@/components/studio/dashboard-sidebar";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { useAgentEndpoint } from "@/lib/agent-endpoint";
import { AgentProvider, useAgentContext } from "@/lib/agent-provider";
import { AgentSSEProvider } from "@/lib/agent-sse-provider";
import { useAgentLiveQuerySync } from "@/lib/use-agent";
import { SetupReadiness, parseSetupEndpoint } from "@/lib/setup-readiness";
import { ProjectProvider } from "@/lib/project-provider";
import { cn } from "@/lib/utils";
import { FeatureFlagProvider } from "@gen/featureflags";

// Search params for optional project selection or auto-demo entry.
//
// `demo` stays numeric after validation so TanStack's canonical search
// serialization preserves the marketing entrypoint as `?demo=1` instead of
// redirecting to a quoted JSON string (`?demo=%221%22`).
interface StudioSearchParams {
  project?: string;
  setup?: string;
  agent?: string;
  demo?: 1 | "1";
}

export const Route = createFileRoute("/studio")({
  component: StudioLayout,
  validateSearch: (search: Record<string, unknown>): StudioSearchParams => {
    return {
      setup:
        typeof search.setup === "string" && /^[a-f0-9]{64}$/.test(search.setup)
          ? search.setup
          : undefined,
      agent:
        typeof search.agent === "string" && parseSetupEndpoint(search.agent)
          ? search.agent
          : undefined,
      project: typeof search.project === "string" ? search.project : undefined,
      demo:
        search.demo === 1 || search.demo === "1" || search.demo === true || search.demo === "true"
          ? 1
          : undefined,
    };
  },
});

function StudioLayout() {
  const { project, demo, setup, agent: setupAgent } = Route.useSearch();
  const { endpoint, isDemo, bootingDemo, useDemo, useLocal } = useAgentEndpoint();
  useEffect(() => {
    if (!setup && !setupAgent) return;
    const local = setupAgent ? parseSetupEndpoint(setupAgent) : null;
    if (local && (isDemo || endpoint.host !== local.host || endpoint.port !== local.port))
      useLocal(local);
    else if (isDemo) useLocal();
  }, [setup, setupAgent, isDemo, endpoint.host, endpoint.port, useLocal]);
  const navigate = useNavigate({ from: "/studio" });
  const demoEntryConsumedRef = useRef(false);

  // `?demo=1` is the marketing entry-point: flip into demo mode on mount.
  useEffect(() => {
    if (setup || setupAgent || !demo || isDemo || demoEntryConsumedRef.current) return;
    demoEntryConsumedRef.current = true;
    void useDemo().finally(() => {
      void navigate({
        search: (prev) => ({ ...prev, demo: undefined }),
        replace: true,
      });
    });
  }, [demo, isDemo, navigate, useDemo, setup, setupAgent]);

  const { host, port, token } = endpoint;
  // Force a clean remount of SSE/Agent providers whenever the endpoint
  // changes so internal connection state (EventSource, polling timers,
  // cached health) doesn't leak across local <-> demo transitions.
  const providerKey = `${endpoint.kind}:${host}:${port}`;

  if (bootingDemo) {
    return (
      <div className="flex h-svh items-center justify-center text-muted-foreground">
        Booting demo agent…
      </div>
    );
  }

  return (
    // SSE provider is outside so AgentProvider can consume SSE status for health
    <AgentSSEProvider
      setupSession={setup}
      projectId={project}
      key={`sse:${providerKey}`}
      host={host}
      port={port}
      token={token}
    >
      <AgentProvider key={`agent:${providerKey}`} host={host} port={port} token={token}>
        <AgentQuerySync />
        <ProjectProvider initialProjectId={isDemo ? "demo" : project}>
          {setup && project ? <SetupReadiness session={setup} projectId={project} /> : null}
          <FeatureFlagProvider>
            <SidebarProvider>
              <DashboardSidebar />
              {/* <SidebarTrigger /> */}
              <SidebarInset>
                {isDemo && <DemoBanner />}
                <DashboardHeader />
                <EnsureAgent isDemo={isDemo} />
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

function EnsureAgent({ isDemo }: { isDemo: boolean }) {
  const { isConnected } = useAgentContext();
  const location = useLocation();
  const isOverview = location.pathname === "/studio";
  const isSetup = location.pathname === "/studio/setup";

  // In demo mode the (mocked) agent is always "connected" — never show the
  // pairing UI or the disabled overlay.
  const isAgentVisible = useMemo(() => {
    if (isDemo) return false;
    if (isSetup) return !isConnected;
    return !isConnected;
  }, [isDemo, isSetup, isConnected]);

  const isOverlayVisible = useMemo(() => {
    if (isDemo) return false;
    if (isOverview) return false;
    if (isSetup) return false;
    return !isConnected;
  }, [isDemo, isSetup, isConnected, isOverview]);

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
