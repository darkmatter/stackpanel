import { createFileRoute } from "@tanstack/react-router";
import { ProcessesPanel } from "@/components/studio/panels/processes";

export const Route = createFileRoute("/studio/processes")({
  component: ProcessesRoute,
});

function ProcessesRoute() {
  return <ProcessesPanel />;
}
