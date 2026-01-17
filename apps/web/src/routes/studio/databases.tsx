import { createFileRoute } from "@tanstack/react-router";
import { DatabasesPanel } from "@/components/studio/panels/databases-panel";

export const Route = createFileRoute("/studio/databases")({
	component: DatabasesRoute,
});

function DatabasesRoute() {
	return <DatabasesPanel />;
}
