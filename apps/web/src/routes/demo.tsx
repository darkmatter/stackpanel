import { createFileRoute } from "@tanstack/react-router";
import { DashboardShell } from "@/components/studio/dashboard-shell";
import { AgentProvider } from "@/lib/agent-provider";

export const Route = createFileRoute("/demo")({
  loader: async ({ context }) => {
    // Prefetch project data on the server
    // These will be cached and available immediately on client
    const { trpc, queryClient } = context;

    // Prefetch in parallel - these are public endpoints so no token needed
    await Promise.all([
      queryClient.prefetchQuery(
        trpc.agent.listProjects.queryOptions({ host: "localhost", port: 9876 }),
      ),
      queryClient.prefetchQuery(
        trpc.agent.currentProject.queryOptions({
          host: "localhost",
          port: 9876,
        }),
      ),
      queryClient.prefetchQuery(
        trpc.agent.health.queryOptions({ host: "localhost", port: 9876 }),
      ),
    ]).catch(() => {
      // Agent might not be running - that's okay, client will retry
    });

    return {};
  },
  component: DemoPage,
});

function DemoPage() {
  return (
    <AgentProvider>
      <DashboardShell />
    </AgentProvider>
  );
}
