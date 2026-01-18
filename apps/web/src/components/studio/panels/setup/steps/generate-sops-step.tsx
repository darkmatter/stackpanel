"use client";

import { Button } from "@ui/button";
import { Check, CheckCircle2, FileCog, Loader2, RefreshCw } from "lucide-react";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function GenerateSopsStep() {
	const {
		expandedStep,
		setExpandedStep,
		identityInfo,
		sopsConfigGenerated,
		handleGenerateSopsConfig,
		isGeneratingSops,
	} = useSetupContext();

	const step: SetupStep = {
		id: "generate-config",
		title: "Generate SOPS Config",
		description: "Generate .sops.yaml with your encryption keys",
		status: sopsConfigGenerated
			? "complete"
			: identityInfo?.type
				? "incomplete"
				: "blocked",
		required: true,
		dependsOn: ["decryption-key"],
		icon: <FileCog className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "generate-config"}
			onToggle={() =>
				setExpandedStep(
					expandedStep === "generate-config" ? null : "generate-config",
				)
			}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					Generate your <code>.sops.yaml</code> configuration file with all
					configured encryption keys (AGE, SSH, KMS).
				</p>

				{sopsConfigGenerated ? (
					<div className="space-y-4">
						<div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-4">
							<p className="text-sm text-emerald-700 dark:text-emerald-300 flex items-center gap-2">
								<CheckCircle2 className="h-4 w-4" />
								SOPS configuration generated successfully!
							</p>
							<p className="text-xs text-muted-foreground mt-2">
								Your <code>.sops.yaml</code> file is ready. You can now create
								encrypted secrets.
							</p>
						</div>

						<Button
							variant="outline"
							onClick={handleGenerateSopsConfig}
							disabled={isGeneratingSops}
						>
							{isGeneratingSops ? (
								<Loader2 className="h-4 w-4 animate-spin mr-2" />
							) : (
								<RefreshCw className="h-4 w-4 mr-2" />
							)}
							Regenerate Config
						</Button>
					</div>
				) : (
					<Button
						onClick={handleGenerateSopsConfig}
						disabled={isGeneratingSops}
					>
						{isGeneratingSops ? (
							<Loader2 className="h-4 w-4 animate-spin mr-2" />
						) : (
							<Check className="h-4 w-4 mr-2" />
						)}
						Generate .sops.yaml
					</Button>
				)}
			</div>
		</StepCard>
	);
}
