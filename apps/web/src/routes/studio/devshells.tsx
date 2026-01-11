import { createFileRoute } from "@tanstack/react-router";
import { DevShellsPanel } from "@/components/studio/panels/dev-shells-panel";

export const Route = createFileRoute("/studio/devshells")({
  component: DevShellsRoute,
});

function DevShellsRoute() {
  return <DevShellsPanel />;
}
