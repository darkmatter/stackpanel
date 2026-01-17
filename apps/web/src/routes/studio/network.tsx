import { createFileRoute } from "@tanstack/react-router";
import { NetworkPanel } from "@/components/studio/panels/network-panel";

export const Route = createFileRoute("/studio/network")({
	component: NetworkRoute,
});

function NetworkRoute() {
	return <NetworkPanel />;
}
