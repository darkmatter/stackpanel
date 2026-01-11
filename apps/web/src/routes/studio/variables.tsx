import { createFileRoute } from "@tanstack/react-router";
import { VariablesPanel } from "@/components/studio/panels/variables-panel";

export const Route = createFileRoute("/studio/variables")({
  component: VariablesRoute,
});

function VariablesRoute() {
  return <VariablesPanel />;
}
