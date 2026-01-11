import { createFileRoute } from "@tanstack/react-router";
import { CommandsPanel } from "@/components/studio/panels/commands-panel";

export const Route = createFileRoute("/studio/commands")({
  component: CommandsRoute,
});

function CommandsRoute() {
  return <CommandsPanel />;
}
