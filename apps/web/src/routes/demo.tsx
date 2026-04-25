import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { DashboardHeader } from "@/components/studio/dashboard-header";
import { DashboardSidebar } from "@/components/studio/dashboard-sidebar";
import { OverviewPanel } from "@/components/studio/panels/overview-panel";
import {
	SidebarInset,
	SidebarProvider,
} from "@/components/ui/sidebar";
import { DemoBanner } from "@/components/demo/demo-banner";
import { AgentProvider } from "@/lib/agent-provider";
import { ProjectProvider } from "@/lib/project-provider";
import { FeatureFlagProvider } from "@gen/featureflags";
import { DEMO_HOST, DEMO_PORT } from "@/demo/fixture";
import { DEMO_TOKEN } from "@/demo/token";
import { startDemoWorker } from "@/demo/worker";

export const Route = createFileRoute("/demo")({
	component: DemoLayout,
	head: () => ({
		meta: [
			{ title: "Stackpanel Studio · Live demo" },
			{
				name: "description",
				content:
					"Click around the real Stackpanel Studio against an in-browser mocked agent. No install required.",
			},
		],
	}),
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
							<DemoBanner />
							<DashboardHeader />
							<main className="flex-1 overflow-auto px-6 py-4 min-h-0">
								<OverviewPanel />
							</main>
						</SidebarInset>
					</SidebarProvider>
				</FeatureFlagProvider>
			</ProjectProvider>
		</AgentProvider>
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
