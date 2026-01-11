import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/demo")({
  beforeLoad: () => {
    // Redirect /demo to /studio
    throw redirect({ to: "/studio" });
  },
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
  component: () => null,
});
