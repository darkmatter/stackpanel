"use client";

import { Card, CardContent } from "@ui/card";
import { Progress } from "@ui/progress";
import { TooltipProvider } from "@ui/tooltip";
import {
	Check,
	CheckCircle2,
	Cloud,
	Database,
	FileCog,
	FolderOpen,
	Loader2,
	Shield,
	ShieldCheck,
	Terminal,
	Users,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import {
	type KMSConfigResponse,
	type Project,
} from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import {
	useNixConfig,
	useNixData,
	useVariablesBackend,
	useRecipients,
	useRekeyWorkflowStatus,
} from "@/lib/use-agent";
import { HelpButton } from "../shared/help-button";

import { SetupProvider } from "./setup-context";
import {
	ConnectAgentStep,
	InitGroupsStep,
	InfrastructureStep,
	KmsConfigStep,
	ProjectInfoStep,
	SecretsBackendStep,
	TeamAccessStep,
	VerifyConfigStep,
} from "./steps";
import type { SetupContextValue, SetupStep, SSTData } from "./types";

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
	const { data: nixConfig, isLoading: nixConfigLoading } = useNixConfig();
	const [expandedStep, setExpandedStep] = useState<string | null>(
		initialStep || "connect-agent",
	);
	const [isLoading, setIsLoading] = useState(true);

	// Sync with URL changes
	useEffect(() => {
		if (initialStep) {
			setExpandedStep(initialStep);
		}
	}, [initialStep]);

	// Project info state
	const [projectInfo, setProjectInfo] = useState<Project | null>(null);
	const [projectConfirmed, setProjectConfirmed] = useState(false);

	// Step states
	const [kmsConfig, setKmsConfig] = useState<KMSConfigResponse | null>(null);
	const [groupsInitialized, setGroupsInitialized] = useState<
		Record<string, boolean>
	>({});
	const [groupsVerified, setGroupsVerified] = useState<
		Record<string, boolean>
	>({});
	const [configVerified, setConfigVerified] = useState(false);

	// SST/Infrastructure state
	const { data: sstData, mutate: setSstData } = useNixData<SSTData>("sst", {
		initialData: {},
	});
	const [sstFormData, setSstFormData] = useState<SSTData>({});
	const [sstSaving, setSstSaving] = useState(false);

	// Recipients and rekey workflow (fetched via hooks)
	const { data: recipientsData } = useRecipients();
	const { data: _rekeyWorkflowData } = useRekeyWorkflowStatus();
	const recipientsCount =
		(recipientsData as { recipients?: { length: number } } | undefined)
			?.recipients?.length ?? 0;

	// Derive values from config
	const projectName =
		((nixConfig as Record<string, unknown>)?.name as string) ||
		projectInfo?.name ||
		"Unknown";
	const githubRepo =
		((nixConfig as Record<string, unknown>)?.github as string) || "";
	const homeDir = (nixConfig as Record<string, unknown>)?.dirs as
		| Record<string, unknown>
		| undefined;
	const homeDirPath = (homeDir?.home as string) || ".stackpanel";
	const dataPath = `${homeDirPath}/data/`;
	const genPath = `${homeDirPath}/gen/`;
	const statePath = `${homeDirPath}/state/`;

	// Extract inherited AWS config
	const awsConfig = (nixConfig as Record<string, unknown>)?.aws as
		| Record<string, unknown>
		| undefined;
	const rolesAnywhere = awsConfig?.["roles-anywhere"] as
		| Record<string, unknown>
		| undefined;
	const inheritedRegion = (rolesAnywhere?.region as string) || "us-west-2";
	const inheritedAccountId = (rolesAnywhere?.["account-id"] as string) || "";

	// Parse GitHub org/repo
	const [githubOrg, githubRepoName] = githubRepo.includes("/")
		? githubRepo.split("/")
		: ["", "*"];

	// Check if AWS KMS is configured
	const hasAwsKms = sstData?.kms?.enable ?? false;

	// Secrets backend
	const { data: backendData } = useVariablesBackend();
	const secretsBackend: "vals" | "chamber" = backendData?.backend ?? "vals";
	const isChamber = secretsBackend === "chamber";

	// ==========================================================================
	// Data Loading
	// ==========================================================================

	const loadConfig = useCallback(async () => {
		if (!token) return;
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

		// Check if groups are initialized by listing group secrets
		try {
			const groupList = await client.listGroupSecrets();
			if ("groups" in groupList) {
				const groups = groupList.groups as Record<string, string[]>;
				const initMap: Record<string, boolean> = {};
				for (const g of Object.keys(groups)) {
					initMap[g] = true;
				}
				setGroupsInitialized(initMap);
			}
		} catch {
			setGroupsInitialized({});
		}

		setIsLoading(false);
	}, [token, agentClient]);

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
						repo:
							sstData.oidc?.["github-actions"]?.repo || githubRepoName || "*",
						branch: sstData.oidc?.["github-actions"]?.branch || "*",
					},
					flyio: {
						"org-id": sstData.oidc?.flyio?.["org-id"] || "",
						"app-name": sstData.oidc?.flyio?.["app-name"] || "*",
					},
					"roles-anywhere": {
						"trust-anchor-arn":
							sstData.oidc?.["roles-anywhere"]?.["trust-anchor-arn"] || "",
					},
				},
				iam: {
					"role-name":
						sstData.iam?.["role-name"] || `${projectName}-secrets-role`,
				},
			});
		}
	}, [
		sstData,
		projectName,
		inheritedRegion,
		inheritedAccountId,
		githubOrg,
		githubRepoName,
	]);

	// ==========================================================================
	// Handlers
	// ==========================================================================

	const handleSaveSST = async () => {
		setSstSaving(true);
		try {
			await setSstData(sstFormData);
			toast.success("Infrastructure configuration saved");
			setExpandedStep("init-groups");
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
		setExpandedStep("secrets-backend");
	};

	const goToStep = (stepId: string) => {
		setExpandedStep(stepId);
	};

	// ==========================================================================
	// Build Steps (for progress calculation)
	// ==========================================================================

	const steps: SetupStep[] = [
		{
			id: "connect-agent",
			title: "Connect to Agent",
			description: "Install the CLI and connect",
			status: isConnected ? "complete" : "incomplete",
			required: true,
			icon: <Terminal className="h-5 w-5" />,
		},
		{
			id: "project-info",
			title: "Confirm Directories",
			description: "Understand project structure",
			status: projectConfirmed
				? "complete"
				: isConnected
					? "incomplete"
					: "blocked",
			required: true,
			dependsOn: ["connect-agent"],
			icon: <FolderOpen className="h-5 w-5" />,
		},
		{
			id: "secrets-backend",
			title: "Secrets Backend",
			description: "Choose how secrets are managed",
			status: secretsBackend
				? "complete"
				: projectConfirmed
					? "incomplete"
					: "blocked",
			required: true,
			dependsOn: ["project-info"],
			icon: <Database className="h-5 w-5" />,
		},
		{
			id: "infrastructure",
			title: "AWS Infrastructure",
			description: "Deploy KMS and IAM roles",
			status: sstData?.enable ? "complete" : isChamber ? "incomplete" : "optional",
			required: isChamber,
			dependsOn: ["secrets-backend"],
			icon: <Cloud className="h-5 w-5" />,
		},
		{
			id: "init-groups",
			title: "Initialize Groups",
			description: "Generate group encryption keys",
			status: isChamber
				? "complete"
				: groupsVerified
					? "complete"
					: groupsInitialized
						? "incomplete"
						: secretsBackend
							? "incomplete"
							: "blocked",
			required: !isChamber,
			dependsOn: ["secrets-backend"],
			icon: <ShieldCheck className="h-5 w-5" />,
		},
		{
			id: "team-access",
			title: "Team Access",
			description: "Manage encryption recipients",
			status: isChamber
				? "complete"
				: recipientsCount > 0
					? "complete"
					: "optional",
			required: false,
			icon: <Users className="h-5 w-5" />,
		},
		{
			id: "kms",
			title: "AWS KMS Config",
			description: "Use existing KMS key",
			status: isChamber ? "complete" : kmsConfig?.enable ? "complete" : "optional",
			required: false,
			icon: <Shield className="h-5 w-5" />,
		},
		{
			id: "verify-config",
			title: "Verify Configuration",
			description: "Confirm secrets are working",
			status: isChamber
				? "complete"
				: configVerified
					? "complete"
					: groupsVerified
						? "incomplete"
						: "blocked",
			required: !isChamber,
			dependsOn: ["init-groups"],
			icon: <FileCog className="h-5 w-5" />,
		},
	];

	const completedSteps = steps.filter((s) => s.status === "complete").length;
	const requiredSteps = steps.filter((s) => s.required);
	const requiredComplete = requiredSteps.filter(
		(s) => s.status === "complete",
	).length;
	const progress = (completedSteps / steps.length) * 100;

	// ==========================================================================
	// Context Value
	// ==========================================================================

	const contextValue: SetupContextValue = {
		// Navigation
		expandedStep,
		setExpandedStep,
		goToStep,

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

		// Secrets backend
		secretsBackend,
		isChamber,
	};

	// ==========================================================================
	// Render
	// ==========================================================================

	if (isLoading || nixConfigLoading) {
		return (
			<div className="flex items-center justify-center py-12">
				<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
			</div>
		);
	}

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
								Complete these steps to configure secrets management for your
								project.
							</p>
						</div>
					</div>

					{/* Progress */}
					<Card>
						<CardContent>
							<div className="flex items-center justify-between mb-3 -mt-1">
								<div className="flex items-center gap-2">
									<span className="text-sm font-medium">Setup Progress</span>
									<span className="text-sm text-muted-foreground">
										({requiredComplete}/{requiredSteps.length} required)
									</span>
								</div>
								<span className="text-sm font-medium">
									{Math.round(progress)}%
								</span>
							</div>
							<Progress value={progress} className="h-2" />
							{requiredComplete === requiredSteps.length && (
								<p className="text-sm text-emerald-500 mt-3 flex items-center gap-2">
									<CheckCircle2 className="h-4 w-4" />
									All required steps complete! Your project is ready to use
									secrets.
								</p>
							)}
						</CardContent>
					</Card>

					{/* Steps */}
					<div className="space-y-4">
						<ConnectAgentStep />
						<ProjectInfoStep />
						<SecretsBackendStep />
						<InfrastructureStep />
						<InitGroupsStep />
						<TeamAccessStep />
						<KmsConfigStep />
						<VerifyConfigStep />
					</div>

					{/* Next Steps */}
					{requiredComplete === requiredSteps.length && (
						<Card className="bg-linear-to-r from-emerald-400/10 to-blue-400/10 border-emerald-500/20">
							<CardContent className="pt-6">
								<h3 className="font-semibold text-lg mb-2">
									Setup Complete!
								</h3>
								<p className="text-sm text-muted-foreground mb-4">
									Your project is ready for secrets management. Here's what you
									can do next:
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
