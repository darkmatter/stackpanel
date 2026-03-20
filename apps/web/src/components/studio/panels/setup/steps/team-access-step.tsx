"use client";

import { Users } from "lucide-react";
import { RecipientsSection } from "../../variables/recipients-section";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function TeamAccessStep() {
	const { expandedStep, setExpandedStep, isChamber } = useSetupContext();

	const step: SetupStep = {
		id: "team-access",
		title: "Recipients",
		description: "Add team member public keys that SOPS encrypts to",
		status: isChamber ? "complete" : "optional",
		required: false,
		icon: <Users className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "team-access"}
			onToggle={() =>
				setExpandedStep(expandedStep === "team-access" ? null : "team-access")
			}
		>
			<div className="space-y-3">
				<p className="text-sm text-muted-foreground">
					Recipients are AGE or SSH public keys that SOPS encrypts to.
					Adding your key here links it to creation rules so files can
					be decrypted by your machine.
				</p>
				<RecipientsSection />
			</div>
		</StepCard>
	);
}
