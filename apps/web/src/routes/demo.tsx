import { createFileRoute, Outlet } from "@tanstack/react-router";
import {
	SidebarInset,
	SidebarProvider,
} from "@/components/ui/sidebar";
import { DemoBanner } from "@/components/demo/demo-banner";
import { DemoHeader } from "@/components/demo/demo-header";
import { DemoSidebar } from "@/components/demo/demo-sidebar";

export const Route = createFileRoute("/demo")({
	component: DemoLayout,
	head: () => ({
		meta: [
			{ title: "Stackpanel Studio · Live demo" },
			{
				name: "description",
				content:
					"Click around a fully interactive Stackpanel Studio with realistic fixture data. No install required.",
			},
		],
	}),
});

function DemoLayout() {
	return (
		<SidebarProvider>
			<DemoSidebar />
			<SidebarInset>
				<DemoBanner />
				<DemoHeader />
				<main className="flex-1 overflow-auto">
					<Outlet />
				</main>
			</SidebarInset>
		</SidebarProvider>
	);
}
