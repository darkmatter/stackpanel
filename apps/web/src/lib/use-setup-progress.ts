"use client";

import {
	Cloud,
	Database,
	FileCog,
	FolderOpen,
	KeyRound,
	type LucideIcon,
	Shield,
	ShieldCheck,
	Terminal,
	Users,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useAgentContext, useAgentClient } from "./agent-provider";
import { useNixData, useVariablesBackend } from "./use-agent";

// =============================================================================
// Types
// =============================================================================

export type StepStatus =
	| "complete"
	| "incomplete"
	| "in-progress"
	| "optional"
	| "blocked";

export interface SetupStep {
	id: string;
	title: string;
	shortTitle: string;
	description: string;
	status: StepStatus;
	required: boolean;
	dependsOn?: string[];
	icon: LucideIcon;
}

export interface SetupProgress {
	steps: SetupStep[];
	complete: number;
	total: number;
	requiredComplete: number;
	requiredTotal: number;
	isComplete: boolean;
}

// =============================================================================
// SST Data Type
// =============================================================================

interface SSTData {
	enable?: boolean;
	kms?: {
		enable?: boolean;
	};
}

// =============================================================================
// Hook
// =============================================================================

export function useSetupProgress(): SetupProgress | null {
	const { token, isConnected } = useAgentContext();
	const agentClient = useAgentClient();
	const [progress, setProgress] = useState<SetupProgress | null>(null);

	// Load SST data for infrastructure step
	const { data: sstData } = useNixData<SSTData>("sst", {
		initialData: { enable: false },
	});

	// Load secrets backend
	const { data: backendData } = useVariablesBackend();
	const secretsBackend: "vals" | "chamber" = backendData?.backend ?? "vals";
	const isChamber = secretsBackend === "chamber";

	const loadProgress = useCallback(async () => {
		let projectConfirmed = false;
		let hasInitializedGroups = false;
		let hasRecipients = false;
		let kmsEnabled = false;
		let configVerified = false;
		let sopsKeysReady = false;
		let sopsKeysMatchRecipients = false;

		if (token) {
			try {
				const client = agentClient;

				// Check project confirmed
				projectConfirmed =
					localStorage.getItem("stackpanel-project-confirmed") === "true";

				// Check if any SOPS creation rules exist
				try {
					const nixConfig = await client.nix.config();
					const config = (nixConfig as { config?: { secrets?: { "creation-rules"?: unknown[] } } }).config;
					const secrets = (config?.secrets ?? {}) as {
						"creation-rules"?: unknown[];
					};
					hasInitializedGroups = (secrets["creation-rules"]?.length ?? 0) > 0;
				} catch {
					// Ignore
				}

				// Check recipients
				try {
					const recipientsResp = await client.listRecipients();
					hasRecipients = recipientsResp.recipients.length > 0;
				} catch {
					// Ignore
				}

				// Check KMS config
				try {
					const kmsConfig = await client.getKMSConfig();
					kmsEnabled = kmsConfig?.enable ?? false;
				} catch {
					// Ignore
				}

				try {
					const sopsKeyStatus = await client.getSopsAgeKeysStatus();
					sopsKeysReady = sopsKeyStatus.available;
					sopsKeysMatchRecipients = sopsKeyStatus.recipientMatch;
				} catch {
					// Ignore
				}

			// Check config verification (.stack/secrets/.sops.yaml exists)
			try {
				await client.readFile(
					".stack/secrets/.sops.yaml",
				);
					configVerified = true;
					hasInitializedGroups = true;
				} catch {
					// File doesn't exist
				}
			} catch (err) {
				console.warn("Failed to load setup progress:", err);
			}
		}

		const steps: SetupStep[] = [
			{
				id: "connect-agent",
				title: "Connect to Agent",
				shortTitle: "Connect",
				description:
					"Install the CLI and connect to your local Stackpanel agent",
				status: isConnected ? "complete" : "incomplete",
				required: true,
				icon: Terminal,
			},
			{
				id: "project-info",
				title: "Confirm Directories",
				shortTitle: "State",
				description: "How Stackpanel organizes your project",
				status: projectConfirmed
					? "complete"
					: isConnected
						? "incomplete"
						: "blocked",
				required: true,
				dependsOn: ["connect-agent"],
				icon: FolderOpen,
			},
			{
				id: "secrets-backend",
				title: "Secrets Backend",
				shortTitle: "Backend",
				description: "Choose how secrets are stored and managed",
				status: secretsBackend
					? "complete"
					: projectConfirmed
						? "incomplete"
						: "blocked",
				required: true,
				dependsOn: ["project-info"],
				icon: Database,
			},
			{
				id: "sops-age-keys",
				title: "Decryption Keys",
				shortTitle: "Keys",
				description: "Confirm that sops-age-keys can return at least one AGE private key",
				status: isChamber
					? "complete"
					: sopsKeysReady && sopsKeysMatchRecipients
						? "complete"
						: projectConfirmed
							? "incomplete"
							: "blocked",
				required: !isChamber,
				dependsOn: ["secrets-backend"],
				icon: KeyRound,
			},
			{
				id: "infrastructure",
				title: "AWS Auto-Config",
				shortTitle: "Auto-Deploy (AWS)",
				description:
					"Automatically create required AWS resources for production-ready secrets management",
				status: sstData?.enable
					? "complete"
					: isChamber
						? "incomplete"
						: "optional",
				required: isChamber,
				dependsOn: ["sops-age-keys"],
				icon: Cloud,
			},
			{
				id: "init-groups",
				title: "Review Groups",
				shortTitle: "Groups",
				description: isChamber
					? "Not needed for Chamber backend"
					: "Review SOPS group files and verify encryption",
				status: isChamber
					? "complete"
					: hasInitializedGroups
						? "complete"
						: projectConfirmed
							? "incomplete"
							: "blocked",
				required: !isChamber,
				dependsOn: ["sops-age-keys"],
				icon: ShieldCheck,
			},
			{
				id: "team-access",
				title: "Team Access",
				shortTitle: "Team",
				description:
					"Manage team members who can access encrypted secrets",
				status: isChamber
					? "complete"
					: hasRecipients
						? "complete"
						: "optional",
				required: false,
				icon: Users,
			},
			{
				id: "kms",
				title: "AWS KMS Config",
				shortTitle: "KMS",
				description:
					"Configure your local machine to use an existing AWS KMS key",
				status: isChamber
					? "complete"
					: kmsEnabled
						? "complete"
						: "optional",
				required: false,
				icon: Shield,
			},
			{
				id: "verify-config",
				title: "Verify Configuration",
				shortTitle: "Verify",
				description:
					"Verify SOPS configuration is auto-generated and working",
				status: isChamber
					? "complete"
					: configVerified
						? "complete"
						: hasInitializedGroups
							? "incomplete"
							: "blocked",
				required: !isChamber,
				dependsOn: ["init-groups"],
				icon: FileCog,
			},
		];

		const complete = steps.filter((s) => s.status === "complete").length;
		const requiredSteps = steps.filter((s) => s.required);
		const requiredComplete = requiredSteps.filter(
			(s) => s.status === "complete",
		).length;

		setProgress({
			steps,
			complete,
			total: steps.length,
			requiredComplete,
			requiredTotal: requiredSteps.length,
			isComplete: requiredComplete === requiredSteps.length,
		});
	}, [token, isConnected, sstData, agentClient, secretsBackend, isChamber]);

	useEffect(() => {
		loadProgress();
	}, [loadProgress]);

	return progress;
}
