"use client";

import { Button } from "@ui/button";
import { Badge } from "@ui/badge";
import { Card, CardContent } from "@ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { TooltipProvider } from "@ui/tooltip";
import {
  AlertTriangle,
  CheckCircle2,
  Loader2,
  Shield,
  Users,
  VariableIcon,
} from "lucide-react";
import { useEffect, useMemo } from "react";
import { useAgentContext } from "@/lib/agent-provider";
import { useModuleHealth } from "@/lib/healthchecks/use-healthchecks";
import { useVariables, useVariablesBackend } from "@/lib/use-agent";
import { useNixConfig } from "@/lib/use-agent";
import { PanelHeader } from "../shared/panel-header";
import { AddVariableDialog } from "./add-variable-dialog";
import { type VariablesBackend } from "./constants";
import { EditSecretDialog } from "./edit-secret-dialog";
import { useSopsConfigStatus } from "./use-sops-config-status";
import { ManageTab } from "./components/manage-tab";
import { ConfigureTab } from "./components/configure-tab";
import { RecipientsTab } from "./components/recipients-tab";
import { useVariablesUIStore } from "./store/variables-ui-store";
import { useVariableFilters } from "./hooks/use-variable-filters";

export function VariablesPanel() {
  const { data: variables, isLoading, error, refetch } = useVariables();
  const { token, isConnected } = useAgentContext();
  const { data: backendData } = useVariablesBackend();
  const { data: nixConfig } = useNixConfig();
  const nixSecrets = ((nixConfig as Record<string, unknown>)?.secrets as Record<string, unknown> | undefined);
  const isChamber = (nixSecrets?.backend as string | undefined) === "chamber";
  const backend: VariablesBackend = isChamber ? "chamber" : "vals";
  const sopsConfigStatus = useSopsConfigStatus();

  const { data: sopsHealth } = useModuleHealth("sops", {
    enabled: isConnected && !isChamber,
  });

  // Check if at least one valid decryption method is configured
  const hasValidDecryptionMethod = useMemo(() => {
    if (isChamber) return true;
    if (!sopsHealth?.checks) return null;
    const decryptionCheckIds = ["sops-age-key-available", "sops-kms-access"];
    return sopsHealth.checks.some(
      (check) =>
        decryptionCheckIds.includes(check.checkId) &&
        check.status === "HEALTH_STATUS_HEALTHY",
    );
  }, [sopsHealth, isChamber]);

  // Zustand store selectors
  const editingSecret = useVariablesUIStore(
    (state: any) => state.editingSecret,
  );
  const setEditingSecret = useVariablesUIStore(
    (state: any) => state.setEditingSecret,
  );

  // Build variables list from raw data
  const variablesList = useMemo(() => {
    if (!variables) return [];
    return Object.entries(variables).map(([id, variable]) => {
      const value =
        typeof variable === "string" ? variable : (variable?.value ?? "");
      const varId = typeof variable === "string" ? id : (variable?.id ?? id);
      const name = varId;
      const envKey = varId.split("/").pop() ?? varId;
      return {
        id: varId,
        value,
        name,
        envKey,
      };
    });
  }, [variables]);

  // Use filtering hook
  const { filteredVariables, totalVariables } = useVariableFilters(
    variablesList,
    backend,
  );

  // Reset store on component unmount
  useEffect(() => {
    return () => {
      // Optionally reset state on unmount
      // useVariablesUIStore.getState().reset();
    };
  }, []);

  if (isLoading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="border-destructive/40">
        <CardContent className="space-y-4 py-8 text-center">
          <p className="text-destructive">
            Error loading variables: {error.message}
          </p>
          <Button variant="outline" onClick={() => refetch()}>
            Retry
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <TooltipProvider>
      <div className="space-y-6">
        <PanelHeader
          title="Variables & Secrets"
          description={`${totalVariables} variable${totalVariables !== 1 ? "s" : ""} defined`}
          guideKey="variables"
          size="lg"
          actions={<AddVariableDialog onSuccess={refetch} />}
        />

        <Tabs defaultValue="manage" className="w-full">
          <TabsList className="grid w-full grid-cols-3 max-w-2xl">
            <TabsTrigger value="manage" className="flex items-center gap-2">
              <VariableIcon className="h-4 w-4" />
              Manage
            </TabsTrigger>
            <TabsTrigger value="configure" className="flex items-center gap-2">
              <Shield className="h-4 w-4" />
              Configure
              {sopsConfigStatus.needsAttention ? (
                <Badge
                  variant="outline"
                  className="ml-1 px-1.5 py-0 border-amber-500/40 text-amber-600"
                >
                  <AlertTriangle className="h-3 w-3" />
                </Badge>
              ) : null}
              {hasValidDecryptionMethod === true && (
                <CheckCircle2 className="h-3.5 w-3.5 text-green-500" />
              )}
              {hasValidDecryptionMethod === false && (
                <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />
              )}
            </TabsTrigger>
            <TabsTrigger value="recipients" className="flex items-center gap-2">
              <Users className="h-4 w-4" />
              Recipients
            </TabsTrigger>
          </TabsList>

          <TabsContent value="manage">
            <ManageTab
              filteredVariables={filteredVariables}
              backend={backend}
              token={token}
              onSuccess={refetch}
            />
          </TabsContent>

          <TabsContent value="configure">
            <ConfigureTab isChamber={isChamber} backendData={backendData} />
          </TabsContent>

          <TabsContent value="recipients">
            <RecipientsTab />
          </TabsContent>
        </Tabs>

        {editingSecret && (
          <EditSecretDialog
            secretId={editingSecret.id}
            secretKey={editingSecret.key}
            open={!!editingSecret}
            onOpenChange={(open) => {
              if (!open) setEditingSecret(null);
            }}
            onSuccess={() => {
              refetch();
            }}
          />
        )}
      </div>
    </TooltipProvider>
  );
}
