import { createFileRoute } from "@tanstack/react-router";
import { OverviewPanel } from "@/components/studio/panels/overview-panel";

export const Route = createFileRoute("/studio/")({
	component: OverviewRoute,
});

function OverviewRoute() {
	return <OverviewPanel />;
}
