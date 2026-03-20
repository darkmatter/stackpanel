"use client";

import {
	Cloud,
	FileCog,
	FolderOpen,
	type LucideIcon,
	ShieldCheck,
	Terminal,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useAgentContext, useAgentClient } from "./agent-provider";
import { useNixData } from "./use-agent";

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

	// Chamber is detected from Nix config, not a mutable UI selector
	const [isChamber, setIsChamber] = useState(false);

	const loadProgress = useCallback(async () => {
		let projectConfirmed = false;
		let hasInitializedGroups = false;
		let hasRecipients = false;
		let configVerified = false;
		let sopsKeysReady = false;
		let sopsKeysMatchRecipients = false;

		if (token) {
			try {
				const client = agentClient;

				// Check project confirmed
				projectConfirmed =
					localStorage.getItem("stackpanel-project-confirmed") === "true";

				// Detect chamber mode from Nix config
				try {
					const nixCfg = await client.nix.config();
					const cfgSecrets = ((nixCfg as { config?: { secrets?: { backend?: string } } }).config?.secrets);
					setIsChamber((cfgSecrets?.backend ?? "") === "chamber");
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
			id: "secrets",
			title: "Secrets",
			shortTitle: "Secrets",
			description: "Generate local key, add sources, configure recipients, verify round-trip",
			status: isChamber
				? "complete"
				: sopsKeysReady && sopsKeysMatchRecipients && hasRecipients
					? "complete"
					: projectConfirmed
						? "incomplete"
						: "blocked",
			required: !isChamber,
			dependsOn: ["project-info"],
			icon: ShieldCheck,
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
			dependsOn: ["secrets"],
			icon: Cloud,
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
	}, [token, isConnected, sstData, agentClient, isChamber]);

	useEffect(() => {
		loadProgress();
	}, [loadProgress]);

	return progress;
}
