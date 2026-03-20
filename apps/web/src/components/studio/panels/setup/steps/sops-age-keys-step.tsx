"use client";

import { KeyRound } from "lucide-react";
import { useSopsAgeKeysStatus, useNixEntityData } from "@/lib/use-agent";
import type { SecretsConfigEntity } from "@/lib/types";
import { KeySourcesConfig } from "../../variables/key-sources-config";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function SopsAgeKeysStep() {
	const { expandedStep, setExpandedStep, isChamber, goToStep } = useSetupContext();
	const { data: status } = useSopsAgeKeysStatus();
	const { data: secretsConfig, set } = useNixEntityData<SecretsConfigEntity>("secrets");

	const step: SetupStep = {
		id: "sops-age-keys",
		title: "Decryption Keys",
		description: "Configure which key sources sops-age-keys uses and confirm one matches a configured recipient",
		status: isChamber
			? "complete"
			: status?.available && status?.recipientMatch
				? "complete"
				: "incomplete",
		required: !isChamber,
		icon: <KeyRound className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "sops-age-keys"}
			onToggle={() => setExpandedStep(expandedStep === "sops-age-keys" ? null : "sops-age-keys")}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					Add key sources, validate each one, then click <strong>Re-check</strong> to
					confirm at least one returned public key matches a configured recipient.
					Reload the shell after saving to apply changes.
				</p>

				<KeySourcesConfig
					config={secretsConfig ?? {}}
					onSave={async (next) => {
						await set(next as SecretsConfigEntity);
					}}
				/>

				{status?.available && status?.recipientMatch ? (
					<button
						type="button"
						className="text-sm underline text-muted-foreground"
						onClick={() => goToStep("init-groups")}
					>
						Continue to SOPS Config →
					</button>
				) : null}
			</div>
		</StepCard>
	);
}
