"use client";

import { useNavigate } from "@tanstack/react-router";
import { Card, CardContent } from "@ui/card";
import { Progress } from "@ui/progress";
import { TooltipProvider } from "@ui/tooltip";
import { Check, CheckCircle2, Loader2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { type KMSConfigResponse, type Project } from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useNixData, useRecipients, useSopsAgeKeysStatus } from "@/lib/use-agent";
import { HelpButton } from "../shared/help-button";
import { StudioPanel } from "../shared/studio-panel";
import { useStudioPanels } from "../shared/use-studio-panels";
import { getSetupPanelSteps } from "./panel-steps";
import { StepCard } from "./step-card";

import { SetupProvider } from "./setup-context";
import {
  ConnectAgentStep,
  InfrastructureStep,
  ProjectInfoStep,
  SecretsStep,
  VerifyConfigStep,
} from "./steps";
import type { SetupContextValue, SSTData } from "./types";

// =============================================================================
// Setup Wizard
// =============================================================================

interface SetupWizardProps {
  /** Initial step to expand (from URL search param) */
  initialStep?: string;
}

export function SetupWizard({ initialStep }: SetupWizardProps) {
  const { token, isConnected } = useAgentContext();
  const agentClient = useAgentClient();
  const { config: nixConfig, panels, isLoading: nixConfigLoading, error } = useStudioPanels();
  const panelSteps = getSetupPanelSteps(panels);
  const navigate = useNavigate({ from: "/studio/setup" });
  // No search parameter opens Connect; an explicitly empty step collapses all cards.
  const expandedStep = initialStep === undefined ? "connect-agent" : initialStep || null;
  const setExpandedStep = (step: string | null) => {
    void navigate({ search: (prev) => ({ ...prev, step: step ?? "" }), resetScroll: false });
  };
  const [isLoading, setIsLoading] = useState(true);

  // Project info state
  const [projectInfo, setProjectInfo] = useState<Project | null>(null);
  const [projectConfirmed, setProjectConfirmed] = useState(false);

  // Step states
  const [kmsConfig, setKmsConfig] = useState<KMSConfigResponse | null>(null);
  const [groupsInitialized, setGroupsInitialized] = useState<Record<string, boolean>>({});
  const [groupsVerified, setGroupsVerified] = useState<Record<string, boolean>>({});
  const [configVerified, setConfigVerified] = useState(false);

  // SST/Infrastructure state
  const {
    data: sstData,
    mutate: setSstData,
    error: sstError,
  } = useNixData<SSTData>("sst", {
    initialData: {},
  });
  const [sstFormData, setSstFormData] = useState<SSTData>({});
  const [sstSaving, setSstSaving] = useState(false);

  // Recipients
  const recipients = useRecipients();
  const recipientsCount = recipients.data?.recipients.length ?? 0;
  const keys = useSopsAgeKeysStatus();

  // Derive values from config
  const projectName =
    ((nixConfig as Record<string, unknown>)?.name as string) || projectInfo?.name || "Unknown";
  const githubRepo = ((nixConfig as Record<string, unknown>)?.github as string) || "";
  const homeDir = (nixConfig as Record<string, unknown>)?.dirs as
    | Record<string, unknown>
    | undefined;
  const homeDirPath = (homeDir?.home as string) || ".stack";
  const dataPath = `${homeDirPath}/data/`;
  const genPath = `${homeDirPath}/gen/`;
  const statePath = `${homeDirPath}/state/`;

  // Extract inherited AWS config
  const awsConfig = (nixConfig as Record<string, unknown>)?.aws as
    | Record<string, unknown>
    | undefined;
  const rolesAnywhere = awsConfig?.["roles-anywhere"] as Record<string, unknown> | undefined;
  const inheritedRegion = (rolesAnywhere?.region as string) || "us-west-2";
  const inheritedAccountId = (rolesAnywhere?.["account-id"] as string) || "";

  // Parse GitHub org/repo
  const [githubOrg, githubRepoName] = githubRepo.includes("/") ? githubRepo.split("/") : ["", "*"];

  // Check if AWS KMS is configured
  const hasAwsKms = sstData?.kms?.enable ?? false;

  // Chamber mode is determined solely by Nix config, not a UI selector
  const nixSecrets = (nixConfig as Record<string, unknown>)?.secrets as
    | Record<string, unknown>
    | undefined;
  const isChamber = (nixSecrets?.backend as string | undefined) === "chamber";

  // ==========================================================================
  // Data Loading
  // ==========================================================================

  const loadConfig = useCallback(async () => {
    if (!isConnected) return;
    setIsLoading(true);

    const client = agentClient;

    // Load project info
    try {
      const projectRes = await client.getCurrentProject();
      if (projectRes.project) {
        setProjectInfo(projectRes.project);
      }
    } catch {
      // Project endpoint may not be available - use defaults from nixConfig
    }

    // Check if project was previously confirmed
    const confirmed = localStorage.getItem("stackpanel-project-confirmed");
    setProjectConfirmed(confirmed === "true");

    // Load KMS config
    try {
      const kms = await client.getKMSConfig();
      setKmsConfig(kms);
    } catch {
      // KMS endpoint may not be available - use defaults
      setKmsConfig(null);
    }

    const secretsConfig = nixConfig?.secrets as { groups?: Record<string, unknown> } | undefined;
    const groupsConfig = secretsConfig?.groups ?? {};
    const initMap: Record<string, boolean> = {};
    for (const groupName of Object.keys(groupsConfig)) {
      initMap[groupName] = true;
    }
    setGroupsInitialized(initMap);

    setIsLoading(false);
  }, [isConnected, agentClient, nixConfig]);

  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  // Sync SST form data with config
  useEffect(() => {
    if (sstData) {
      setSstFormData({
        enable: sstData.enable ?? false,
        "project-name": sstData["project-name"] || projectName,
        region: sstData.region || inheritedRegion,
        "account-id": sstData["account-id"] || inheritedAccountId,
        "config-path": sstData["config-path"] || "packages/infra/sst.config.ts",
        kms: {
          enable: sstData.kms?.enable ?? true,
          alias: sstData.kms?.alias || `${projectName}-secrets`,
          "deletion-window-days": sstData.kms?.["deletion-window-days"] ?? 30,
        },
        oidc: {
          provider: sstData.oidc?.provider || "github-actions",
          "github-actions": {
            org: sstData.oidc?.["github-actions"]?.org || githubOrg,
            repo: sstData.oidc?.["github-actions"]?.repo || githubRepoName || "*",
            branch: sstData.oidc?.["github-actions"]?.branch || "*",
          },
          flyio: {
            "org-id": sstData.oidc?.flyio?.["org-id"] || "",
            "app-name": sstData.oidc?.flyio?.["app-name"] || "*",
          },
          "roles-anywhere": {
            "trust-anchor-arn": sstData.oidc?.["roles-anywhere"]?.["trust-anchor-arn"] || "",
          },
        },
        iam: {
          "role-name": sstData.iam?.["role-name"] || `${projectName}-secrets-role`,
        },
      });
    }
  }, [sstData, projectName, inheritedRegion, inheritedAccountId, githubOrg, githubRepoName]);

  // ==========================================================================
  // Handlers
  // ==========================================================================

  const handleSaveSST = async () => {
    setSstSaving(true);
    try {
      await setSstData(sstFormData);
      toast.success("Infrastructure configuration saved");
      setExpandedStep("verify-config");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setSstSaving(false);
    }
  };

  const confirmProject = () => {
    localStorage.setItem("stackpanel-project-confirmed", "true");
    setProjectConfirmed(true);
    toast.success("Project configuration confirmed");
    setExpandedStep("secrets");
  };

  // ==========================================================================
  // Build Steps (for progress calculation)
  // ==========================================================================

  // Module panels have no completion contract. Only the built-in steps can
  // contribute to the required progress, never the act of opening a panel.
  const secretsError = keys.error?.message || keys.data?.error || recipients.error?.message;
  const secretsReady =
    !secretsError &&
    keys.data?.localKeyExists &&
    keys.data.available &&
    keys.data.recipientMatch &&
    recipientsCount > 0;
  const requiredSteps = [
    isConnected,
    projectConfirmed,
    ...(isChamber ? [!sstError && sstData?.enable === true] : [secretsReady, configVerified]),
  ];
  const requiredComplete = requiredSteps.filter(Boolean).length;
  const progress = (requiredComplete / requiredSteps.length) * 100;
  const catalogReady = isConnected && !nixConfigLoading && !error && !!nixConfig;
  const coreReady = catalogReady && !isLoading;
  const setupComplete = coreReady && requiredComplete === requiredSteps.length;
  const unknownStep =
    expandedStep &&
    !["connect-agent", "project-info", "secrets", "infrastructure", "verify-config"].includes(
      expandedStep,
    ) &&
    !panelSteps.some(({ id }) => id === expandedStep);

  // ==========================================================================
  // Context Value
  // ==========================================================================

  const contextValue: SetupContextValue = {
    // Navigation
    expandedStep,
    setExpandedStep,
    goToStep: setExpandedStep,

    // Agent
    isConnected,
    token,

    // Project info
    projectName,
    githubRepo,
    homeDirPath,
    dataPath,
    genPath,
    statePath,
    projectConfirmed,
    confirmProject,

    // AWS/SST
    sstData: sstData ?? null,
    sstFormData,
    setSstFormData,
    handleSaveSST,
    sstSaving,
    hasAwsKms,

    // Groups
    groupsInitialized,
    setGroupsInitialized,
    groupsVerified,
    setGroupsVerified,

    // Team access
    recipientsCount,

    // KMS
    kmsConfig,

    // Config verification
    configVerified,
    setConfigVerified,

    // Chamber mode (from Nix config)
    isChamber,
  };

  // ==========================================================================
  // Render
  // ==========================================================================

  return (
    <SetupProvider value={contextValue}>
      <TooltipProvider>
        <div className="space-y-8 max-w-3xl">
          {/* Header */}
          <div className="flex items-start gap-2">
            <div>
              <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
                Project Setup
                <HelpButton guideKey="setup" tooltip="Setup guide" />
              </h1>
              <p className="text-muted-foreground mt-2">
                Complete these steps to configure secrets management for your project.
              </p>
            </div>
          </div>

          {/* Progress */}
          {coreReady && (
            <Card>
              <CardContent>
                <div className="flex items-center justify-between mb-3 -mt-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium">Required setup progress</span>
                    <span className="text-sm text-muted-foreground">
                      ({requiredComplete}/{requiredSteps.length} required)
                    </span>
                  </div>
                  <span className="text-sm font-medium">{Math.round(progress)}%</span>
                </div>
                <Progress value={progress} className="h-2" />
                {setupComplete && (
                  <p className="text-sm text-emerald-500 mt-3 flex items-center gap-2">
                    <CheckCircle2 className="h-4 w-4" />
                    All required steps complete! Your project is ready to use secrets.
                  </p>
                )}
              </CardContent>
            </Card>
          )}

          <div className="space-y-4">
            <ConnectAgentStep />
            {!isConnected ? (
              <p className="text-sm text-muted-foreground">
                Connect to the agent to load project setup steps.
              </p>
            ) : error ? (
              <p role="alert" className="text-sm text-destructive">
                Could not load setup configuration: {error.message}
              </p>
            ) : nixConfigLoading || isLoading ? (
              <p role="status" className="flex items-center gap-2 text-sm text-muted-foreground">
                <Loader2 className="size-4 animate-spin" /> Loading setup steps…
              </p>
            ) : !nixConfig ? (
              <p role="alert" className="text-sm text-destructive">
                Setup configuration is unavailable.
              </p>
            ) : (
              <>
                {unknownStep && (
                  <p role="status" className="text-sm text-muted-foreground">
                    This setup step is not available.
                  </p>
                )}
                <ProjectInfoStep />
                {secretsError && (
                  <p role="alert" className="text-sm text-destructive">
                    Secrets status is unavailable: {secretsError}
                  </p>
                )}
                <SecretsStep />
                {sstError ? (
                  <p role="alert" className="text-sm text-destructive">
                    Infrastructure configuration is unavailable: {sstError.message}
                  </p>
                ) : (
                  <InfrastructureStep />
                )}
                <VerifyConfigStep />
              </>
            )}
            {catalogReady &&
              panelSteps.map(({ id, label, description, icon: Icon, panel }) => (
                <StepCard
                  key={id}
                  step={{
                    id,
                    title: label,
                    description,
                    status: "optional",
                    required: false,
                    icon: <Icon className="size-5" />,
                  }}
                  isExpanded={expandedStep === id}
                  onToggle={() => setExpandedStep(expandedStep === id ? null : id)}
                >
                  <StudioPanel panel={panel} />
                </StepCard>
              ))}
          </div>

          {/* Next Steps */}
          {setupComplete && (
            <Card className="bg-linear-to-r from-emerald-400/10 to-blue-400/10 border-emerald-500/20">
              <CardContent className="pt-6">
                <h3 className="font-semibold text-lg mb-2">Setup Complete!</h3>
                <p className="text-sm text-muted-foreground mb-4">
                  Your project is ready for secrets management. Here's what you can do next:
                </p>
                <ul className="space-y-2 text-sm">
                  <li className="flex items-center gap-2">
                    <Check className="h-4 w-4 text-emerald-100" />
                    Create secrets in the Variables panel
                  </li>
                  {isChamber ? (
                    <>
                      <li className="flex items-center gap-2">
                        <Check className="h-4 w-4 text-emerald-100" />
                        Use <code>chamber write</code> to add secrets to AWS SSM
                      </li>
                      <li className="flex items-center gap-2">
                        <Check className="h-4 w-4 text-emerald-100" />
                        Secrets are injected via <code>chamber env</code> at runtime
                      </li>
                    </>
                  ) : (
                    <>
                      <li className="flex items-center gap-2">
                        <Check className="h-4 w-4 text-emerald-100" />
                        Use <code>secrets:set KEY --group dev --value VALUE</code> via CLI
                      </li>
                      <li className="flex items-center gap-2">
                        <Check className="h-4 w-4 text-emerald-100" />
                        New team members auto-register when entering the devshell
                      </li>
                    </>
                  )}
                </ul>
              </CardContent>
            </Card>
          )}
        </div>
      </TooltipProvider>
    </SetupProvider>
  );
}
