import { createFileRoute } from "@tanstack/react-router";
import { PackagesPanel } from "@/components/studio/panels/packages-panel";

export const Route = createFileRoute("/studio/packages")({
	component: PackagesRoute,
});

function PackagesRoute() {
	return <PackagesPanel />;
}
