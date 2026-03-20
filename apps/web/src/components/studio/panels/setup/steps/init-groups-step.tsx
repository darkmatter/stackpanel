"use client";

import { Shield } from "lucide-react";
import { GroupsSection } from "../../variables/groups-section";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import { useSopsConfigStatus } from "../../variables/use-sops-config-status";
import type { SetupStep } from "../types";

export function InitGroupsStep() {
	const { expandedStep, setExpandedStep, isChamber } = useSetupContext();
	const status = useSopsConfigStatus();

	const step: SetupStep = {
		id: "init-groups",
		title: "SOPS Config",
		description: "Configure recipient groups and creation rules for .stack/secrets/.sops.yaml",
		status: isChamber
			? "complete"
			: !status.needsAttention
				? "complete"
				: "incomplete",
		required: !isChamber,
		dependsOn: ["secrets-backend"],
		icon: <Shield className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "init-groups"}
			onToggle={() =>
				setExpandedStep(expandedStep === "init-groups" ? null : "init-groups")
			}
		>
			<div className="space-y-3">
				<p className="text-sm text-muted-foreground">
					Configure recipient groups and SOPS creation rules.
					This generates <code>.stack/secrets/.sops.yaml</code> on each shell
					reload, controlling which keys can encrypt and decrypt each secret file.
				</p>
				<GroupsSection />
			</div>
		</StepCard>
	);
}
