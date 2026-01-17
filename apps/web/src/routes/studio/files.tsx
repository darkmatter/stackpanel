/**
 * Files Page
 *
 * Displays generated files from stackpanel.files.entries.
 * Shows file metadata, staleness status, and allows regeneration.
 */

import { createFileRoute } from "@tanstack/react-router";
import { FilesPanel } from "@/components/studio/panels/files-panel";

export const Route = createFileRoute("/studio/files")({
	component: FilesPage,
});

function FilesPage() {
	return (
		<div className="container mx-auto py-8">
			<FilesPanel />
		</div>
	);
}
