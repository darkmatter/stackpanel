/**
 * Inspector Page
 *
 * Provides a comprehensive view of the Stackpanel environment for debugging
 * and inspection purposes. Shows generated files, integrations, scripts,
 * state files, and configuration data.
 */

import { createFileRoute } from "@tanstack/react-router";
import { InspectorPanel } from "@/components/studio/panels/inspector-panel";

export const Route = createFileRoute("/studio/inspector")({
	component: InspectorPage,
});

function InspectorPage() {
	return (
		<div className="container mx-auto py-8">
			<InspectorPanel />
		</div>
	);
}
