import { createFileRoute } from "@tanstack/react-router";
import { SetupWizard } from "@/components/studio/panels/setup/setup-wizard";

export const Route = createFileRoute("/studio/setup")({
	component: SetupRoute,
});

function SetupRoute() {
	return <SetupWizard />;
}
