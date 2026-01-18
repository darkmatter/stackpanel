import { createFileRoute } from "@tanstack/react-router";
import { InfraPanel } from "@/components/studio/panels/infra-panel";

export const Route = createFileRoute("/studio/infra")({
	component: InfraRoute,
});

function InfraRoute() {
	return <InfraPanel />;
}
