import { createFileRoute } from "@tanstack/react-router";
import { ChecksPanel } from "@/components/studio/panels/checks-panel";

export const Route = createFileRoute("/studio/checks")({
	component: ChecksRoute,
});

function ChecksRoute() {
	return <ChecksPanel />;
}
