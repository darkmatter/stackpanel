import { createFileRoute } from "@tanstack/react-router";
import { LocalConfigPanel } from "@/components/studio/panels/local-config-panel";

export const Route = createFileRoute("/studio/local-config")({
	component: LocalConfigRoute,
});

function LocalConfigRoute() {
	return <LocalConfigPanel />;
}
