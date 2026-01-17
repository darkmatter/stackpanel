import { createFileRoute } from "@tanstack/react-router";
import { TeamPanel } from "@/components/studio/panels/team-panel";

export const Route = createFileRoute("/studio/team")({
	component: TeamRoute,
});

function TeamRoute() {
	return <TeamPanel />;
}
