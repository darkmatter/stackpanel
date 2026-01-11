import { createFileRoute } from "@tanstack/react-router";
import { TerminalPanel } from "@/components/studio/panels/terminal-panel";

export const Route = createFileRoute("/studio/terminal")({
  component: TerminalRoute,
});

function TerminalRoute() {
  return <TerminalPanel />;
}
