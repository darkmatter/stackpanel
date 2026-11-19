import { createClient, type Transport } from "@connectrpc/connect";
import { ProjectService } from "@stackpanel/proto/agent/v1/project";
import { useQuery } from "@tanstack/react-query";
import { useEffect } from "react";

/** Resolve once, then pin the ID. Never operate on a changing implicit current project. */
export function useInitialAgentProject({
  transport,
  host,
  port,
  agentId,
  root,
  selected,
  select,
}: {
  transport: Transport;
  host: string;
  port: number;
  agentId: string | null;
  root: string | null;
  selected: string | null;
  select: (id: string) => void;
}) {
  const discovery = useQuery({
    queryKey: ["agent", "initial-project", host, port, agentId, root],
    enabled: !!agentId && !selected,
    queryFn: async ({ signal }) => {
      const { projects, defaultProjectId } = await createClient(ProjectService, transport)
        .listProjects({}, { signal });
      // Only pin a usable registered project. A public current path is not authority to select one.
      const match = projects.find(
        (project) => project.valid && (root ? project.path === root : project.id === defaultProjectId),
      );
      return match?.id || null;
    },
    refetchInterval: !selected && agentId ? 5000 : false,
    retry: false,
  });
  useEffect(() => {
    if (agentId && !selected && discovery.data) select(discovery.data);
  }, [agentId, selected, select, discovery.data]);
  return !selected && agentId ? discovery.error : null;
}
