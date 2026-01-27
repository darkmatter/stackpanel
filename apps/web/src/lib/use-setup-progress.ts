"use client";

import {
	Cloud,
	Database,
	FileCog,
	FolderOpen,
	Github as _Github,
	GithubIcon,
	Key,
	type LucideIcon,
	Shield,
	Terminal,
	Users as _Users,
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
		let hasIdentity = false;
		let hasSopsConfig = false;
		let usersConfigured = false;
		let kmsEnabled = false;

		if (token) {
			try {
				const client = agentClient;

				// Check project confirmed
				projectConfirmed =
					localStorage.getItem("stackpanel-project-confirmed") === "true";

				// Check identity
				try {
					const identity = await client.getAgeIdentity();
					hasIdentity = identity.type !== "";
				} catch {
					// Ignore
				}

				// Check SOPS config
				try {
					await client.readFile(".sops.yaml");
					hasSopsConfig = true;
				} catch {
					// File doesn't exist
				}

				// Check users.yaml
				try {
					const usersFile = await client.readFile(
						".stackpanel/secrets/users.yaml",
					);
					const hasPublicKeys =
						usersFile.content?.includes("public-key:") ?? false;
					usersConfigured = hasPublicKeys;
				} catch {
					// File doesn't exist
				}

				// Check KMS config
				try {
					const kmsConfig = await client.getKMSConfig();
					kmsEnabled = kmsConfig?.enable ?? false;
				} catch {
					// Ignore
				}
			} catch (err) {
				console.warn("Failed to load setup progress:", err);
			}
		}

		const hasAwsKms = sstData?.kms?.enable ?? false;

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
				id: "infrastructure",
				title: "AWS Auto-Config",
				shortTitle: "Auto-Deploy (AWS)",
				description:
					"Automatically create required AWS resources for production-ready secrets management",
				status: sstData?.enable ? "complete" : isChamber ? "incomplete" : "optional",
				required: isChamber,
				dependsOn: ["secrets-backend"],
				icon: Cloud,
			},
			{
				id: "decryption-key",
				title: "Local Decryption Key",
				shortTitle: "AGE Key",
				description: isChamber
					? "Not needed for Chamber backend"
					: hasAwsKms
						? "Optional if using AWS KMS"
						: "Configure your private key for decrypting secrets locally",
				status: isChamber
					? "complete"
					: hasIdentity
						? "complete"
						: hasAwsKms
							? "optional"
							: projectConfirmed
								? "incomplete"
								: "blocked",
				required: !isChamber && !hasAwsKms,
				dependsOn: ["secrets-backend"],
				icon: Key,
			},
			{
				id: "team-keys",
				title: "Team Sync",
				shortTitle: "Github Sync",
				description: "Sync team members' public keys for encryption",
				status: isChamber ? "complete" : usersConfigured ? "complete" : "optional",
				required: false,
				icon: GithubIcon,
			},
			{
				id: "kms",
				title: "AWS KMS Config",
				shortTitle: "KMS",
				description:
					"Configure your local machine to use an existing AWS KMS key",
				status: isChamber ? "complete" : kmsEnabled ? "complete" : "optional",
				required: false,
				icon: Shield,
			},
			{
				id: "generate-config",
				title: "Generate SOPS Config",
				shortTitle: "SOPS",
				description: "Generate .sops.yaml with your encryption keys",
				status: isChamber
					? "complete"
					: hasSopsConfig
						? "complete"
						: hasIdentity
							? "incomplete"
							: "blocked",
				required: !isChamber,
				dependsOn: ["decryption-key"],
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
