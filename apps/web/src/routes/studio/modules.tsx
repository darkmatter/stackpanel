import { createFileRoute } from "@tanstack/react-router";
import { ModulesPanel } from "@/components/studio/panels/modules/modules-panel";

export const Route = createFileRoute("/studio/modules")({
  component: ModulesPage,
});

function ModulesPage() {
  return (
    <div className="container mx-auto py-8">
      <ModulesPanel />
    </div>
  );
}
