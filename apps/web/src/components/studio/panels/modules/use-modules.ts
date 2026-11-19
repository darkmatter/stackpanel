import { fromJson, type JsonObject } from "@bufbuild/protobuf";
import { ValueSchema } from "@bufbuild/protobuf/wkt";
import type { Client } from "@connectrpc/connect";
import { createConnectQueryKey, useTransport } from "@connectrpc/connect-query";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useAgentContext, useModuleServiceClient } from "@/lib/agent-provider";
import { agentQueryKeys } from "@/lib/use-agent";
import type { AdoptionDecision } from "./adoption-choices";

function wireAnswers(decisions: readonly AdoptionDecision[]) {
  return decisions.map(({ id, revision, answer }) => ({
    id,
    revision,
    answer: fromJson(ValueSchema, answer),
  }));
}

export function useModuleQueryScope() {
  const { host, port, selectedProjectId, isAuthenticated } = useAgentContext();
  const transport = useTransport();
  // The opaque Connect transport key changes with credentials; never cache the bearer itself.
  const [, { transport: transportId }] = createConnectQueryKey({
    schema: ModuleService,
    transport,
    cardinality: undefined,
  });
  return ["agent", "modules", host, port, selectedProjectId, transportId, isAuthenticated] as const;
}

type ModuleClient = Client<typeof ModuleService>;

function useModuleRpc() {
  const scope = useModuleQueryScope();
  const client = useModuleServiceClient();
  let unavailable: string | undefined;
  if (!scope[6]) unavailable = "Connect to your agent to manage modules.";
  else if (!scope[4]?.trim()) unavailable = "Select a project to manage its modules.";
  function requireClient() {
    if (!client || unavailable) throw new Error(unavailable || "Module service unavailable.");
    return client;
  }
  return { scope, requireClient, unavailable };
}

export function useModuleCatalog(enabled = true) {
  const rpc = useModuleRpc();
  return useQuery({
    queryKey: [...rpc.scope, "catalog"],
    queryFn: ({ signal }) => rpc.requireClient().listModules({}, { signal }),
    enabled,
    staleTime: 30_000,
  });
}

export function useModule(moduleId: string, { enabled = true } = {}) {
  const rpc = useModuleRpc();
  return useQuery({
    queryKey: [...rpc.scope, "detail", moduleId],
    queryFn: async ({ signal }) => {
      const { module: value } = await rpc.requireClient().getModule({ moduleId }, { signal });
      if (!value) throw new Error(`The agent returned no module for ${moduleId}.`);
      if (value.id !== moduleId)
        throw new Error(`The agent returned a different module for ${moduleId}.`);
      return { module: value };
    },
    enabled: enabled && !!moduleId,
    staleTime: 30_000,
  });
}

export function useModuleOutputs(moduleId: string) {
  const rpc = useModuleRpc();
  return useQuery({
    queryKey: [...rpc.scope, "outputs", moduleId],
    queryFn: async ({ signal }) => {
      const { outputs } = await rpc.requireClient().getModuleOutputs({ moduleId }, { signal });
      if (!outputs) throw new Error(`The agent returned no outputs for ${moduleId}.`);
      if (outputs.moduleId !== moduleId)
        throw new Error(`The agent returned another module's outputs for ${moduleId}.`);
      return outputs;
    },
    enabled: !!moduleId,
  });
}

export function useModulePreview(
  moduleId: string,
  enabled: boolean,
  decisions: AdoptionDecision[] = [],
) {
  const rpc = useModuleRpc();
  return useQuery({
    queryKey: [...rpc.scope, "enable-preview", moduleId, decisions],
    queryFn: async ({ signal }) => {
      const { preview } = await rpc
        .requireClient()
        .previewModuleEnable({ moduleId, answers: wireAnswers(decisions) }, { signal });
      if (!preview) throw new Error(`The agent returned no enable plan for ${moduleId}.`);
      if (!preview.files || !preview.packages || !preview.services)
        throw new Error(
          `Incomplete enable plan for ${moduleId}: expected files, packages and services.`,
        );
      return preview;
    },
    enabled: enabled && !!moduleId,
    refetchOnWindowFocus: false,
  });
}

export function useRegistryModules({ search = "", category = "", tag = "", enabled = true } = {}) {
  const rpc = useModuleRpc();
  return useQuery({
    queryKey: [...rpc.scope, "registry", "list", search, category, tag],
    queryFn: ({ signal }) =>
      rpc.requireClient().listRegistryModules({ query: search, category, tag }, { signal }),
    enabled,
    staleTime: 30_000,
  });
}

export function useRegistryModule(moduleId: string) {
  const rpc = useModuleRpc();
  return useQuery({
    queryKey: [...rpc.scope, "registry", "detail", moduleId],
    queryFn: async ({ signal }) => {
      const { module, readme } = await rpc
        .requireClient()
        .getRegistryModule({ moduleId }, { signal });
      if (!module) throw new Error(`The registry returned no module for ${moduleId}.`);
      if (module.slug !== moduleId)
        throw new Error(`The registry returned a different module for ${moduleId}.`);
      return { module, readme };
    },
    enabled: !!moduleId,
    staleTime: 30_000,
  });
}

function useModuleChange<Input, Result>(
  change: (client: ModuleClient, input: Input) => Promise<Result>,
) {
  const rpc = useModuleRpc();
  const cache = useQueryClient();
  const mutation = useMutation({
    mutationFn: (input: Input) => change(rpc.requireClient(), input),
    // Re-read evaluated state: a successful write doesn't prove a particular lock version or enable state.
    onSettled: async () => {
      await Promise.all([
        cache.invalidateQueries({ queryKey: rpc.scope }),
        cache.invalidateQueries({ queryKey: agentQueryKeys.nixConfig() }),
      ]);
    },
  });
  return { ...mutation, unavailable: rpc.unavailable };
}

export function useSaveModuleConfig(moduleId: string) {
  return useModuleChange((client, settings: JsonObject) =>
    client.updateModuleConfig({ moduleId, settings }),
  );
}

export function useEnableModule(moduleId: string) {
  return useModuleChange((client, decisions: AdoptionDecision[]) =>
    client.enableModule({ moduleId, answers: wireAnswers(decisions) }),
  );
}

export function useDisableModule(moduleId: string) {
  return useModuleChange((client, _: void) => client.disableModule({ moduleId }));
}

type Pin = { moduleId: string; version: string; ref: string };

export function useInstallModule() {
  return useModuleChange(async (client, request: Pin) => {
    const result = await client.installModule(request);
    if (result.moduleId !== request.moduleId)
      throw new Error(`The agent did not confirm installation of ${request.moduleId}.`);
    return result;
  });
}

export function useUpdateModule() {
  return useModuleChange((client, request: Pin) => client.updateModule(request));
}

export function useUninstallModule() {
  return useModuleChange((client, moduleId: string) => client.uninstallModule({ moduleId }));
}
