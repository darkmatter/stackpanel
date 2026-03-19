"use client";

import { Button } from "@ui/button";
import {
  CheckCircle2,
  FolderKey,
  Loader2,
  Shield,
  XCircle,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { useAgentClient } from "@/lib/agent-provider";
import { useNixConfigQuery } from "@/lib/use-agent";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";
import { config } from "zod";

interface GroupStatus {
  name: string;
  verified: boolean;
  verifying: boolean;
  error: string | null;
}

export function InitGroupsStep() {
  const { expandedStep, setExpandedStep, token, isChamber, goToStep } =
    useSetupContext();
  const agentClient = useAgentClient();
  const { data: nixConfig } = useNixConfigQuery();

  const [groups, setGroups] = useState<GroupStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const configRoot = (
    nixConfig as unknown as Record<string, Record<string, unknown>>
  )?.config;

  const groupNamesList = useMemo(() => {
    const secretsConfig = configRoot?.secrets as
      | Record<string, unknown>
      | undefined;
    const groupsConfigMap = (secretsConfig?.groups ?? {}) as Record<
      string,
      Record<string, unknown>
    >;
    return Object.keys(groupsConfigMap);
  }, [configRoot?.secrets]);
  const loadGroups = useCallback(async () => {
    if (!token) {
      setLoading(false);
      return;
    }

    setGroups(
      groupNamesList.map((name) => ({
        name,
        verified: false,
        verifying: false,
        error: null,
      })),
    );
    setLoading(false);
  }, [token, groupNamesList]);

  useEffect(() => {
    loadGroups();
  }, [loadGroups]);

  const handleVerify = async (groupName: string) => {
    setGroups((prev) =>
      prev.map((g) =>
        g.name === groupName ? { ...g, verifying: true, error: null } : g,
      ),
    );

    try {
      const result = await agentClient.verifySecrets(groupName);
      setGroups((prev) =>
        prev.map((g) =>
          g.name === groupName
            ? {
                ...g,
                verified: result.success,
                verifying: false,
                error: result.success
                  ? null
                  : result.error || "Verification failed",
              }
            : g,
        ),
      );
      if (result.success) {
        toast.success(`Group "${groupName}" encrypt/decrypt verified`);
      } else {
        toast.error(`Verification failed for "${groupName}"`);
      }
    } catch (err) {
      setGroups((prev) =>
        prev.map((g) =>
          g.name === groupName
            ? {
                ...g,
                verifying: false,
                error: err instanceof Error ? err.message : "Failed",
              }
            : g,
        ),
      );
    }
  };

  const anyVerified = groups.some((g) => g.verified);

  const step: SetupStep = {
    id: "init-groups",
    title: "Review Secret Groups",
    description: "Groups map to SOPS files and direct recipients",
    status: isChamber ? "complete" : anyVerified ? "complete" : "incomplete",
    required: !isChamber,
    dependsOn: ["secrets-backend"],
    icon: <Shield className="h-5 w-5" />,
  };

  return (
    <StepCard
      step={step}
      isExpanded={expandedStep === "init-groups"}
      onToggle={() =>
        setExpandedStep(expandedStep === "init-groups" ? null : "init-groups")
      }
    >
      <div className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Each configured group becomes a SOPS file like{" "}
          <code>vars/dev.sops.yaml</code>. There is no extra group key to
          initialize anymore.
        </p>

        {loading ? (
          <div className="flex items-center gap-2 py-4">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span className="text-sm text-muted-foreground">
              Loading groups...
            </span>
          </div>
        ) : groups.length === 0 ? (
          <div className="rounded-lg border p-4">
            <p className="text-sm text-muted-foreground">
              No SOPS rules configured. Add them under{" "}
              <code>secrets.creation-rules</code>.
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {groups.map((group) => (
              <div
                key={group.name}
                className="rounded-lg border p-4 flex items-center justify-between"
              >
                <div className="flex items-center gap-3">
                  <FolderKey className="h-4 w-4 text-muted-foreground" />
                  <div>
                    <p className="text-sm font-medium">{group.name}</p>
                    <p className="text-xs text-muted-foreground">
                      {group.verified ? (
                        <span className="text-emerald-500 flex items-center gap-1">
                          <CheckCircle2 className="h-3 w-3" />
                          Verified
                        </span>
                      ) : (
                        "Stored in vars/" + group.name + ".sops.yaml"
                      )}
                    </p>
                    {group.error && (
                      <p className="text-xs text-red-500 flex items-center gap-1 mt-1">
                        <XCircle className="h-3 w-3" />
                        {group.error}
                      </p>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  {!group.verified ? (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => handleVerify(group.name)}
                      disabled={group.verifying}
                    >
                      {group.verifying ? (
                        <Loader2 className="h-3 w-3 animate-spin mr-1" />
                      ) : null}
                      Verify
                    </Button>
                  ) : (
                    <CheckCircle2 className="h-5 w-5 text-emerald-500" />
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {anyVerified && (
          <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3">
            <p className="text-sm text-emerald-700 dark:text-emerald-300 flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4" />
              Groups verified. You can now create secrets.
            </p>
          </div>
        )}

        {anyVerified && (
          <Button variant="outline" onClick={() => goToStep("team-access")}>
            Continue to Team Access
          </Button>
        )}
      </div>
    </StepCard>
  );
}
