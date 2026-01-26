"use client";

import { Card, CardContent } from "@ui/card";
import { Progress } from "@ui/progress";
import { TooltipProvider } from "@ui/tooltip";
import {
	Check,
	CheckCircle2,
	Cloud,
	FileCog,
	FolderOpen,
	Key,
	Loader2,
	Shield,
	Terminal,
	Users,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import {
	type AgeIdentityResponse,
	type KMSConfigResponse,
	type Project,
} from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useNixConfig, useNixData } from "@/lib/use-agent";
import { HelpButton } from "../shared/help-button";

import { SetupProvider } from "./setup-context";
import {
	ConnectAgentStep,
	DecryptionKeyStep,
	GenerateSopsStep,
	InfrastructureStep,
	KmsConfigStep,
	ProjectInfoStep,
	TeamKeysStep,
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
	const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(
		null,
	);
	const [kmsConfig, setKmsConfig] = useState<KMSConfigResponse | null>(null);
	const [usersConfigured, setUsersConfigured] = useState(false);
	const [sopsConfigGenerated, setSopsConfigGenerated] = useState(false);

	// Form states
	const [identityInput, setIdentityInput] = useState("");
	const [isSaving, setIsSaving] = useState(false);
	const [isGeneratingSops, setIsGeneratingSops] = useState(false);

	// SST/Infrastructure state
	const { data: sstData, mutate: setSstData } = useNixData<SSTData>("sst", {
		initialData: {},
	});
	const [sstFormData, setSstFormData] = useState<SSTData>({});
	const [sstSaving, setSstSaving] = useState(false);

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

		// Load identity
		try {
			const identity = await client.getAgeIdentity();
			setIdentityInfo(identity);
			if (identity.type === "path") {
				setIdentityInput(identity.value);
			}
			setUsersConfigured(identity.type !== "");
		} catch {
			// Identity endpoint may not be available - use defaults
			setIdentityInfo(null);
			setUsersConfigured(false);
		}

		// Load KMS config
		try {
			const kms = await client.getKMSConfig();
			setKmsConfig(kms);
		} catch {
			// KMS endpoint may not be available - use defaults
			setKmsConfig(null);
		}

		// Check if .sops.yaml exists
		try {
			await client.readFile(".sops.yaml");
			setSopsConfigGenerated(true);
		} catch {
			setSopsConfigGenerated(false);
		}

		setIsLoading(false);
	}, [token]);

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
			setExpandedStep("decryption-key");
		} catch (err) {
			toast.error(err instanceof Error ? err.message : "Failed to save");
		} finally {
			setSstSaving(false);
		}
	};

	const handleSaveIdentity = async () => {
		if (!token) return;
		setIsSaving(true);
		try {
			const client = agentClient;
			const result = await client.setAgeIdentity(identityInput);
			setIdentityInfo(result);
			setUsersConfigured(true);
			toast.success("Decryption key saved");
			setExpandedStep("generate-config");
		} catch (err) {
			const message = err instanceof Error ? err.message : "Failed to save";
			// Check if the endpoint isn't implemented
			if (
				message === "Error" ||
				message.includes("not found") ||
				message.includes("404")
			) {
				toast.error(
					"Identity endpoint not available. Please update the agent.",
				);
			} else {
				toast.error(message);
			}
		} finally {
			setIsSaving(false);
		}
	};

	const confirmProject = () => {
		localStorage.setItem("stackpanel-project-confirmed", "true");
		setProjectConfirmed(true);
		toast.success("Project configuration confirmed");
		setExpandedStep("infrastructure");
	};

	const goToStep = (stepId: string) => {
		setExpandedStep(stepId);
	};

	const handleGenerateSopsConfig = async () => {
		if (!token) return;
		setIsGeneratingSops(true);
		try {
			const client = agentClient;
			await client.nixGenerate();
			setSopsConfigGenerated(true);
			toast.success(".sops.yaml generated successfully");
		} catch (err) {
			toast.error(err instanceof Error ? err.message : "Failed to generate");
		} finally {
			setIsGeneratingSops(false);
		}
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
			id: "infrastructure",
			title: "AWS Infrastructure",
			description: "Deploy KMS and IAM roles",
			status: sstData?.enable ? "complete" : "optional",
			required: false,
			dependsOn: ["project-info"],
			icon: <Cloud className="h-5 w-5" />,
		},
		{
			id: "decryption-key",
			title: "Local Decryption Key",
			description: "Configure local key",
			status: identityInfo?.type
				? "complete"
				: hasAwsKms
					? "optional"
					: projectConfirmed
						? "incomplete"
						: "blocked",
			required: !hasAwsKms,
			dependsOn: ["project-info"],
			icon: <Key className="h-5 w-5" />,
		},
		{
			id: "team-keys",
			title: "Team Sync",
			description: "Add team public keys",
			status: usersConfigured ? "complete" : "optional",
			required: false,
			icon: <Users className="h-5 w-5" />,
		},
		{
			id: "kms",
			title: "AWS KMS Config",
			description: "Use existing KMS key",
			status: kmsConfig?.enable ? "complete" : "optional",
			required: false,
			icon: <Shield className="h-5 w-5" />,
		},
		{
			id: "generate-config",
			title: "Generate SOPS Config",
			description: "Create .sops.yaml",
			status: sopsConfigGenerated
				? "complete"
				: identityInfo?.type
					? "incomplete"
					: "blocked",
			required: true,
			dependsOn: ["decryption-key"],
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

		// Identity/Keys
		identityInfo,
		identityInput,
		setIdentityInput,
		handleSaveIdentity,
		isSaving,

		// Users/Team
		usersConfigured,

		// KMS
		kmsConfig,

		// SOPS
		sopsConfigGenerated,
		handleGenerateSopsConfig,
		isGeneratingSops,
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
						<InfrastructureStep />
						<DecryptionKeyStep />
						<TeamKeysStep />
						<KmsConfigStep />
						<GenerateSopsStep />
					</div>

					{/* Next Steps */}
					{requiredComplete === requiredSteps.length && (
						<Card className="bg-linear-to-r from-emerald-400/10 to-blue-400/10 border-emerald-500/20">
							<CardContent className="pt-6">
								<h3 className="font-semibold text-lg mb-2">
									🎉 Setup Complete!
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
									<li className="flex items-center gap-2">
										<Check className="h-4 w-4 text-emerald-100" />
										Use <code>sops</code> to encrypt/decrypt files
									</li>
									<li className="flex items-center gap-2">
										<Check className="h-4 w-4 text-emerald-100" />
										Run <code>generate-sops-secrets</code> to create environment
										YAML files
									</li>
								</ul>
							</CardContent>
						</Card>
					)}
				</div>
			</TooltipProvider>
		</SetupProvider>
	);
}
