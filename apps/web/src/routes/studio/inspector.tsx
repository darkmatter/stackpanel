/**
 * Inspector Page
 *
 * Provides a comprehensive view of the Stackpanel environment for debugging
 * and inspection purposes. Shows generated files, integrations, scripts,
 * state files, and configuration data.
 */

import { createFileRoute } from "@tanstack/react-router";
import { InspectorPanel } from "@/components/studio/panels/inspector-panel";

interface InspectorSearchParams {
  contributor?: string;
}

export const Route = createFileRoute("/studio/inspector")({
  component: InspectorPage,
  validateSearch: (search: Record<string, unknown>): InspectorSearchParams => {
    return {
      contributor: typeof search.contributor === "string" ? search.contributor : undefined,
    };
  },
});

function InspectorPage() {
  const { contributor } = Route.useSearch();
  return (
    <div className="container mx-auto py-8">
      <InspectorPanel initialContributor={contributor} />
    </div>
  );
}
