import { createFileRoute } from "@tanstack/react-router";
import { AppsPanelAlt } from "@/components/studio/panels/apps-panel-alt";

export const Route = createFileRoute("/studio/apps")({
  component: AppsRoute,
});

function AppsRoute() {
  return <AppsPanelAlt />;
}
