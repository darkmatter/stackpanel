import { useIsMutating, useMutation, useQueryClient } from "@tanstack/react-query";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@ui/select";
import { useAgentContext } from "@/lib/agent-provider";
import { agentQueryKeys, useAgentRpcClient, useNixConfigKey } from "@/lib/use-agent";
import {
  type AppProvider,
  type AppProviders,
  appPathSegment,
  compatibleFrameworks,
  planProviderChange,
  type ProviderKind,
} from "./app-providers";

export function ProviderSelect({
  label,
  options,
  enabled,
  disabled,
  onChange,
}: {
  label: string;
  options: AppProvider[];
  enabled: AppProvider[];
  disabled: boolean;
  onChange: (id: string | null) => void;
}) {
  const current = enabled.length === 1 ? enabled[0] : undefined;
  const currentAvailable = current && options.some(({ id }) => id === current.id);
  // Prefix option values so an externally registered provider named "none" is selectable.
  const value = enabled.length === 0 ? "none" : currentAvailable ? `id:${current.id}` : "";
  return (
    <div className="space-y-1">
      <div className="text-xs text-muted-foreground">{label}</div>
      <Select
        value={value}
        disabled={disabled || (options.length === 0 && enabled.length === 0)}
        onValueChange={(choice) => onChange(choice === "none" ? null : choice.slice(3))}
      >
        <SelectTrigger size="sm" aria-label={label} className="w-full">
          <SelectValue placeholder={enabled.map((p) => p.label).join(", ")} />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="none">None</SelectItem>
          {options.map(({ id, label: name }) => (
            <SelectItem key={id} value={`id:${id}`}>
              {name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {enabled.length > 1 && (
        <p className="text-xs text-muted-foreground">
          Multiple enabled; choose one to replace them.
        </p>
      )}
      {current && !currentAvailable && (
        <p className="text-xs text-muted-foreground">Incompatible with the current runtime.</p>
      )}
    </div>
  );
}

export function AppProviderSelectors({
  appId,
  providers,
  disabled = false,
}: {
  appId: string;
  providers: AppProviders;
  disabled?: boolean;
}) {
  const client = useAgentRpcClient();
  const queryClient = useQueryClient();
  const configKey = useNixConfigKey();
  const { host, port, selectedProjectId, projectRoot } = useAgentContext();
  const scope = [host, port, selectedProjectId ?? projectRoot] as const;
  const mutationKey = ["app-provider-selection", ...scope, appId];
  const pending = useIsMutating({ mutationKey, exact: true }) > 0;
  const save = useMutation({
    mutationKey,
    mutationFn: async ({ kind, id }: { kind: ProviderKind; id: string | null }) => {
      if (!client) throw new Error("Not connected to agent");
      const patches = planProviderChange(providers, kind, id);
      let applied = 0;
      try {
        for (const { path, enabled } of patches) {
          const response = await client.patchNixData({
            entity: "apps",
            key: "_root",
            path: `${appPathSegment(appId)}.${path}`,
            valueType: "bool",
            value: JSON.stringify(enabled),
          });
          if (!response.success) throw new Error(response.error || `Could not update ${path}`);
          applied++;
        }
      } catch (cause) {
        if (!applied) throw cause;
        throw new Error(
          `Some changes were saved. ${cause instanceof Error ? cause.message : String(cause)}`,
        );
      } finally {
        // Scope and transport are captured at the start of the save, even if Studio changes projects.
        await Promise.all([
          queryClient.invalidateQueries({
            queryKey: configKey,
            exact: true,
          }),
          queryClient.invalidateQueries({
            queryKey: [...agentQueryKeys.apps(), ...scope],
            exact: true,
          }),
        ]);
      }
    },
  });

  const locked = disabled || !client || pending;
  return (
    <div className="space-y-2">
      <div className="grid gap-4 sm:grid-cols-2">
        <ProviderSelect
          label="Runtime"
          options={providers.runtime}
          enabled={providers.runtime.filter((p) => p.enabled)}
          disabled={locked}
          onChange={(id) => save.mutate({ kind: "runtime", id })}
        />
        <ProviderSelect
          label="Framework"
          options={compatibleFrameworks(providers)}
          enabled={providers.framework.filter((p) => p.enabled)}
          disabled={locked}
          onChange={(id) => save.mutate({ kind: "framework", id })}
        />
      </div>
      {pending && (
        <p role="status" className="text-xs text-muted-foreground">
          Saving provider selection…
        </p>
      )}
      {save.error && (
        <p role="alert" className="text-sm text-destructive">
          Could not save provider selection: {save.error.message}
        </p>
      )}
    </div>
  );
}
