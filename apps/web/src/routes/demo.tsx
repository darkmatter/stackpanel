import { createFileRoute } from "@tanstack/react-router";
import { DashboardShell } from "@/components/studio/dashboard-shell";
import { AgentProvider } from "@/lib/agent-provider";

export const Route = createFileRoute("/demo")({
  component: DemoPage,
});

function DemoPage() {
  return (
    <AgentProvider>
      <DashboardShell />
    </AgentProvider>
  );
}
