import { createFileRoute } from "@tanstack/react-router";
import { ConfigurationPanel } from "@/components/studio/panels/configuration-panel";

export const Route = createFileRoute("/studio/configuration")({
	component: ConfigurationRoute,
});

function ConfigurationRoute() {
	return <ConfigurationPanel />;
}
