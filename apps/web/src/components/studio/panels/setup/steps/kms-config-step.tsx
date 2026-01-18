"use client";

import { Button } from "@ui/button";
import { ExternalLink, Shield } from "lucide-react";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function KmsConfigStep() {
	const { expandedStep, setExpandedStep, kmsConfig } = useSetupContext();

	const step: SetupStep = {
		id: "kms",
		title: "AWS KMS Config (Local)",
		description: "Configure your local machine to use an existing AWS KMS key",
		status: kmsConfig?.enable ? "complete" : "optional",
		required: false,
		icon: <Shield className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "kms"}
			onToggle={() => setExpandedStep(expandedStep === "kms" ? null : "kms")}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					If you already have an AWS KMS key, you can configure SOPS to use it
					for local encryption/decryption. This requires AWS credentials.
				</p>

				<div className="rounded-lg border p-4 space-y-3">
					<h4 className="font-medium text-sm">Prerequisites:</h4>
					<ul className="list-disc list-inside space-y-1 text-sm text-muted-foreground">
						<li>AWS CLI configured with appropriate credentials</li>
						<li>KMS key ARN with encrypt/decrypt permissions</li>
					</ul>
				</div>

				<p className="text-sm text-muted-foreground">
					Configure this in the Configuration panel if you have an existing KMS
					key.
				</p>

				<Button variant="outline" asChild>
					<a
						href="/studio/configuration"
						target="_blank"
						rel="noopener noreferrer"
					>
						<Shield className="h-4 w-4 mr-2" />
						Go to Configuration
						<ExternalLink className="h-3 w-3 ml-2" />
					</a>
				</Button>
			</div>
		</StepCard>
	);
}
