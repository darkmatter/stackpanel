import { createFileRoute } from "@tanstack/react-router";
import { DashboardShell } from "@/components/studio/dashboard-shell";
import { AgentSSEProvider } from "@/lib/agent-sse-provider";
import { AgentProvider } from "@/lib/agent-provider";

export const Route = createFileRoute("/studio/")({
  component: RouteComponent,
});

function RouteComponent() {
  return (
    <AgentProvider>
      <AgentSSEProvider>
        <DashboardShell />
      </AgentSSEProvider>
    </AgentProvider>
  );
}
