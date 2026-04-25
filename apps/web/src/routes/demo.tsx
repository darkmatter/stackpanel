import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { DashboardHeader } from "@/components/studio/dashboard-header";
import { DashboardSidebar } from "@/components/studio/dashboard-sidebar";
import { OverviewPanel } from "@/components/studio/panels/overview-panel";
import {
	SidebarInset,
	SidebarProvider,
} from "@/components/ui/sidebar";
import { AgentProvider } from "@/lib/agent-provider";
import { ProjectProvider } from "@/lib/project-provider";
import { FeatureFlagProvider } from "@gen/featureflags";
import { DEMO_HOST, DEMO_PORT } from "@/demo/fixture";
import { DEMO_TOKEN } from "@/demo/token";
import { startDemoWorker } from "@/demo/worker";

export const Route = createFileRoute("/demo")({
	component: DemoLayout,
});

function DemoLayout() {
	const ready = useDemoWorker();

	if (!ready) {
		return (
			<div className="flex h-screen items-center justify-center text-muted-foreground">
				Booting demo agent…
			</div>
		);
	}

	return (
		<AgentProvider host={DEMO_HOST} port={DEMO_PORT} token={DEMO_TOKEN}>
			<ProjectProvider initialProjectId="demo">
				<FeatureFlagProvider>
					<SidebarProvider>
						<DashboardSidebar />
						<SidebarInset>
							<DashboardHeader />
							<main className="flex-1 overflow-auto px-6 py-4 min-h-0">
								<DemoBanner />
								<OverviewPanel />
							</main>
						</SidebarInset>
					</SidebarProvider>
				</FeatureFlagProvider>
			</ProjectProvider>
		</AgentProvider>
	);
}

function DemoBanner() {
	return (
		<div className="mb-4 rounded-md border border-dashed border-primary/40 bg-primary/5 px-4 py-2 text-sm">
			<strong>Demo mode.</strong> All agent traffic is intercepted in the
			browser by a mock service worker. Nothing here touches a real machine.
		</div>
	);
}

function useDemoWorker(): boolean {
	const [ready, setReady] = useState(false);
	useEffect(() => {
		let cancelled = false;
		startDemoWorker()
			.then(() => {
				if (!cancelled) setReady(true);
			})
			.catch((err) => {
				console.error("[demo] failed to start mock worker", err);
				if (!cancelled) setReady(true); // fall through; handlers won't fire
			});
		return () => {
			cancelled = true;
		};
	}, []);
	return ready;
}
