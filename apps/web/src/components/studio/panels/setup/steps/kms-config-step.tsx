"use client";

import { Cloud } from "lucide-react";
import { KMSSettings } from "../../variables/edit-secret-dialog/kms-settings";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import { useNixEntityData } from "@/lib/use-agent";
import type { SecretsConfigEntity } from "@/lib/types";
import type { SetupStep } from "../types";

export function KmsConfigStep() {
	const { expandedStep, setExpandedStep } = useSetupContext();
	const { data: secretsConfig } = useNixEntityData<SecretsConfigEntity>("secrets");

	const kmsArn = ((secretsConfig?.kms ?? {}) as { "key-arn"?: string })["key-arn"] ?? "";
	const kmsEnabled = kmsArn !== "";

	const step: SetupStep = {
		id: "kms",
		title: "AWS KMS",
		description: "Optionally add an AWS KMS key as a SOPS encryption recipient",
		status: kmsEnabled ? "complete" : "optional",
		required: false,
		icon: <Cloud className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "kms"}
			onToggle={() => setExpandedStep(expandedStep === "kms" ? null : "kms")}
		>
			<div className="space-y-3">
				<p className="text-sm text-muted-foreground">
					Add an AWS KMS key ARN as an additional SOPS recipient. This is stored
					in <code>config.nix</code> and included in every SOPS creation rule.
					Reload the shell after saving to regenerate <code>.stack/secrets/.sops.yaml</code>.
				</p>
				<KMSSettings />
			</div>
		</StepCard>
	);
}
