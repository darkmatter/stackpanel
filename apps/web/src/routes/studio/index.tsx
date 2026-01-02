import { createFileRoute } from "@tanstack/react-router";
import { DashboardShell } from "@/components/demo/dashboard-shell";
import { AgentProvider } from "@/lib/agent-provider";

export const Route = createFileRoute("/studio/")({
	component: RouteComponent,
});

function RouteComponent() {
  return (
    <AgentProvider>
      <DashboardShell />
    </AgentProvider>
  );
}
