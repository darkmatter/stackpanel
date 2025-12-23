import { createFileRoute } from "@tanstack/react-router";
import { DashboardShell } from "@/components/demo/dashboard-shell";

export const Route = createFileRoute("/demo")({
	component: DemoPage,
});

function DemoPage() {
	return <DashboardShell />;
}
