"use client";

import { useEffect } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { RefreshCw, Shield } from "lucide-react";
import { useNixEntityData, useRecipients, useSopsAgeKeysStatus } from "@/lib/use-agent";
import type { SecretsConfigEntity } from "@/lib/types";
import { KeySourcesConfig } from "./key-sources-config";
import { mergeSecretsConfig, useSopsUiOptimisticState } from "./sops-ui-state";
import { useSopsConfigStatus } from "./use-sops-config-status";
import { RecipientGroupsTable } from "./components/recipient-groups-table";
import {
  CreationRulesTable,
  type CreationRule,
} from "./components/creation-rules-table";

export function GroupsSection() {
  const {
    data: secretsConfig,
    refetch,
    set,
    isLoading,
  } = useNixEntityData<SecretsConfigEntity>("secrets");
  const { data: recipients } = useRecipients();
  const { refetch: refetchKeyStatus, isLoading: isCheckingKeys } = useSopsAgeKeysStatus();
  const { optimisticSecretsConfig, update, clearIfSynced } =
    useSopsUiOptimisticState();

  const config = mergeSecretsConfig(secretsConfig, optimisticSecretsConfig);
  const recipientGroups = config["recipient-groups"] ?? {};
  const creationRules = config["creation-rules"] ?? [];
  const recipientList = recipients?.recipients ?? [];
  const recipientNames = recipientList.map((recipient) => recipient.name);
  const recipientNamesSet = new Set(recipientNames);
  const status = useSopsConfigStatus();

  // Normalize recipient groups to ensure recipients is always an array
  const normalizedRecipientGroups = Object.fromEntries(
    Object.entries(recipientGroups).map(([name, group]) => [
      name,
      { recipients: group.recipients ?? [] },
    ]),
  );

  const handleSave = async (next: SecretsConfigEntity) => {
    update({ secretsConfig: next });
    await set(next);
    toast.success("Secrets config updated");
    await refetch();
  };

  useEffect(() => {
    clearIfSynced(undefined, secretsConfig ?? null);
  }, [clearIfSynced, secretsConfig]);

  const onAddGroup = async (name: string, groupRecipients: string[]) => {
    const trimmedName = name.trim();
    if (!trimmedName) {
      toast.error("Group name is required");
      return;
    }
    if (groupRecipients.length === 0) {
      toast.error("Add at least one recipient to the group");
      return;
    }
    const unknown = groupRecipients.filter(
      (recipient) => !recipientNamesSet.has(recipient),
    );
    if (unknown.length > 0) {
      toast.error(`Unknown recipients: ${unknown.join(", ")}`);
      return;
    }
    await handleSave({
      ...config,
      "recipient-groups": {
        ...recipientGroups,
        [trimmedName]: { recipients: groupRecipients },
      },
    });
  };

  const onRemoveGroup = async (name: string) => {
    const nextGroups = { ...recipientGroups };
    delete nextGroups[name];
    await handleSave({
      ...config,
      "recipient-groups": nextGroups,
      "creation-rules": creationRules.map((rule) => ({
        ...rule,
        "recipient-groups": (rule["recipient-groups"] ?? []).filter(
          (group) => group !== name,
        ),
      })),
    });
  };

  const onUpdateGroup = async (
    name: string,
    editingGroupRecipients: string[],
  ) => {
    if (editingGroupRecipients.length === 0) {
      toast.error("Add at least one recipient to the group");
      return;
    }
    const unknown = editingGroupRecipients.filter(
      (recipient) => !recipientNamesSet.has(recipient),
    );
    if (unknown.length > 0) {
      toast.error(`Unknown recipients: ${unknown.join(", ")}`);
      return;
    }
    await handleSave({
      ...config,
      "recipient-groups": {
        ...recipientGroups,
        [name]: { recipients: editingGroupRecipients },
      },
    });
  };

  const onAddRule = async (rule: CreationRule) => {
    const pathRegex = rule["path-regex"]?.trim();
    if (!pathRegex) {
      toast.error("Path regex is required");
      return;
    }
    const unknownRecipients = (rule.recipients ?? []).filter(
      (recipient) => !recipientNamesSet.has(recipient),
    );
    if (unknownRecipients.length > 0) {
      toast.error(`Unknown recipients: ${unknownRecipients.join(", ")}`);
      return;
    }
    const unknownGroups = (rule["recipient-groups"] ?? []).filter(
      (group) => !(group in recipientGroups),
    );
    if (unknownGroups.length > 0) {
      toast.error(`Unknown recipient groups: ${unknownGroups.join(", ")}`);
      return;
    }
    await handleSave({
      ...config,
      "creation-rules": [
        ...creationRules,
        {
          "path-regex": pathRegex,
          recipients: rule.recipients,
          "recipient-groups": rule["recipient-groups"],
        },
      ],
    });
  };

  const onRemoveRule = async (index: number) => {
    await handleSave({
      ...config,
      "creation-rules": creationRules.filter((_, idx) => idx !== index),
    });
  };

  const onUpdateRule = async (index: number, rule: CreationRule) => {
    const pathRegex = rule["path-regex"]?.trim();
    if (!pathRegex) {
      toast.error("Path regex is required");
      return;
    }
    const unknownRecipients = (rule.recipients ?? []).filter(
      (recipient) => !recipientNamesSet.has(recipient),
    );
    if (unknownRecipients.length > 0) {
      toast.error(`Unknown recipients: ${unknownRecipients.join(", ")}`);
      return;
    }
    const unknownGroups = (rule["recipient-groups"] ?? []).filter(
      (group) => !(group in recipientGroups),
    );
    if (unknownGroups.length > 0) {
      toast.error(`Unknown recipient groups: ${unknownGroups.join(", ")}`);
      return;
    }
    await handleSave({
      ...config,
      "creation-rules": creationRules.map((r, i) =>
        i === index
          ? {
              ...r,
              "path-regex": pathRegex,
              recipients: rule.recipients,
              "recipient-groups": rule["recipient-groups"],
            }
          : r,
      ),
    });
  };

  const handleRunKeyCheck = async () => {
    window.dispatchEvent(new CustomEvent("stackpanel:sops-run-check"));
    await refetchKeyStatus();
  };

  if (isLoading) {
    return (
      <Card>
        <CardContent className="py-10 text-center text-muted-foreground">
          Loading SOPS config...
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div className="sticky top-0 z-10 -mx-1 rounded-xl border bg-background/95 px-4 py-3 backdrop-blur supports-backdrop-filter:bg-background/80">
        <div className="flex items-center justify-between gap-3">
          <div>
            <div className="flex items-center gap-2 flex-wrap mb-1">
              <h3 className="text-lg font-medium">SOPS Config</h3>
              {status.missingRecipients ? (
                <Badge variant="destructive">Recipients needed</Badge>
              ) : null}
              {status.missingRecipientGroups ? (
                <Badge variant="outline">No recipient groups</Badge>
              ) : null}
              {status.missingCreationRules ? (
                <Badge variant="outline">No creation rules</Badge>
              ) : null}
            </div>
            <p className="text-sm text-muted-foreground">
              Tell stackpanel how to find your AGE private keys. A command will
              be added to your dev environment as `sops-age-keys` which check
              all the sources you configure here and return the keys.
              `SOPS_AGE_KEY_CMD` is automatically picked up by SOPS allowing you
              to run `sops decrypt{" "}
              <path>` without having to specify additional options.</path>`
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={handleRunKeyCheck}
              className="h-8"
            >
              {isCheckingKeys ? (
                <RefreshCw className="mr-1 h-3.5 w-3.5 animate-spin" />
              ) : (
                <Shield className="mr-1 h-3.5 w-3.5" />
              )}
              Check keys
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => refetch()}
              className="h-8 px-2"
            >
              <RefreshCw className="h-3.5 w-3.5" />
            </Button>
          </div>
        </div>
      </div>

      <KeySourcesConfig config={config} onSave={handleSave} />

      <div className="grid gap-4 xl:grid-cols-2">
        <RecipientGroupsTable
          recipientGroups={normalizedRecipientGroups}
          recipientNames={recipientNames}
          onAddGroup={onAddGroup}
          onRemoveGroup={onRemoveGroup}
          onUpdateGroup={onUpdateGroup}
        />

        <CreationRulesTable
          creationRules={creationRules}
          recipientNames={recipientNames}
          recipientGroupNames={Object.keys(recipientGroups)}
          onAddRule={onAddRule}
          onRemoveRule={onRemoveRule}
          onUpdateRule={onUpdateRule}
        />
      </div>
    </div>
  );
}
