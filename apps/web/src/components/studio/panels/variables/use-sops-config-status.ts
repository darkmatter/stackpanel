import { useEffect, useMemo } from "react";
import { useRecipients, useNixEntityData } from "@/lib/use-agent";
import type { SecretsConfigEntity } from "@/lib/types";
import { mergeRecipients, mergeSecretsConfig, useSopsUiOptimisticState } from "./sops-ui-state";

export function useSopsConfigStatus() {
  const { data: recipients } = useRecipients();
  const { data: secretsConfig } = useNixEntityData<SecretsConfigEntity>("secrets");
  const { optimisticRecipients, optimisticSecretsConfig, clearIfSynced } = useSopsUiOptimisticState();

  useEffect(() => {
    clearIfSynced(recipients?.recipients ?? [], secretsConfig ?? null);
  }, [clearIfSynced, recipients, secretsConfig]);

  return useMemo(() => {
    const mergedRecipients = mergeRecipients(recipients?.recipients ?? [], optimisticRecipients);
    const mergedConfig = mergeSecretsConfig(secretsConfig, optimisticSecretsConfig);
    const recipientGroups = mergedConfig["recipient-groups"] ?? {};
    const creationRules = mergedConfig["creation-rules"] ?? [];

    const missingRecipients = mergedRecipients.length === 0;
    const missingRecipientGroups = Object.keys(recipientGroups).length === 0;
    const missingCreationRules = creationRules.length === 0;
    const needsAttention = missingRecipients || missingRecipientGroups || missingCreationRules;

    return {
      recipients: mergedRecipients,
      secretsConfig: mergedConfig,
      missingRecipients,
      missingRecipientGroups,
      missingCreationRules,
      needsAttention,
    };
  }, [optimisticRecipients, optimisticSecretsConfig, recipients, secretsConfig]);
}
