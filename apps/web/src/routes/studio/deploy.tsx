import { createFileRoute } from "@tanstack/react-router";
import { DeployPanel } from "@/components/studio/panels/deploy/deploy-panel";

export const Route = createFileRoute("/studio/deploy")({
	component: DeployRoute,
});

function DeployRoute() {
	return <DeployPanel />;
}
