import { createFileRoute, Outlet, useLocation } from "@tanstack/react-router";
import { useEffect, useMemo } from "react";
import { AgentConnect } from "@/components/agent-connect";
import { DemoBanner } from "@/components/demo/demo-banner";
import { DashboardHeader } from "@/components/studio/dashboard-header";
import { DashboardSidebar } from "@/components/studio/dashboard-sidebar";
import {
	SidebarInset,
	SidebarProvider,
} from "@/components/ui/sidebar";
import { useAgentEndpoint } from "@/lib/agent-endpoint";
import { AgentProvider, useAgentContext } from "@/lib/agent-provider";
import { AgentSSEProvider } from "@/lib/agent-sse-provider";
import { useAgentLiveQuerySync } from "@/lib/use-agent";
import { ProjectProvider } from "@/lib/project-provider";
import { cn } from "@/lib/utils";
import { FeatureFlagProvider } from "@gen/featureflags";

// Search params for optional project selection or auto-demo entry.
//
// `demo` is intentionally typed as `string` (rather than `boolean`) so the
// search-params record stays a `Record<string, string | undefined>` — that
// shape is what `new URLSearchParams(search)` callers elsewhere in the
// sidebar/panels code rely on. The truthiness check inside `StudioLayout`
// treats any present value as "enable demo", so `?demo=1` (the marketing
// link) and `?demo=true` both work.
interface StudioSearchParams {
	project?: string;
	demo?: string;
}

export const Route = createFileRoute("/studio")({
	component: StudioLayout,
	validateSearch: (search: Record<string, unknown>): StudioSearchParams => {
		return {
			project: typeof search.project === "string" ? search.project : undefined,
			demo:
				search.demo === "1" || search.demo === true || search.demo === "true"
					? "1"
					: undefined,
		};
	},
});

function StudioLayout() {
	const { project, demo } = Route.useSearch();
	const { endpoint, isDemo, bootingDemo, useDemo } = useAgentEndpoint();

	// `?demo=1` is the marketing entry-point: flip into demo mode on mount.
	useEffect(() => {
		if (demo && !isDemo) {
			void useDemo();
		}
	}, [demo, isDemo, useDemo]);

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
			key={`sse:${providerKey}`}
			host={host}
			port={port}
			token={token}
		>
			<AgentProvider
				key={`agent:${providerKey}`}
				host={host}
				port={port}
				token={token}
			>
				<AgentQuerySync />
				<ProjectProvider initialProjectId={isDemo ? "demo" : project}>
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
