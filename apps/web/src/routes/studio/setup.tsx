import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { SetupWizard } from "@/components/studio/panels/setup/setup-wizard";

const setupSearchSchema = z.object({
	step: z.string().optional(),
});

export const Route = createFileRoute("/studio/setup")({
	component: SetupRoute,
	validateSearch: setupSearchSchema,
});

function SetupRoute() {
	const { step } = Route.useSearch();
	return <SetupWizard initialStep={step} />;
}
