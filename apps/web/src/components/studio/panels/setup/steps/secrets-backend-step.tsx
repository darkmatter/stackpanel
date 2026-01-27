"use client";

import { Button } from "@ui/button";
import { CheckCircle2, Database, KeyRound, Loader2, Server } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { usePatchNixData } from "@/lib/use-agent";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

type BackendOption = "vals" | "chamber";

interface BackendChoice {
	id: BackendOption;
	title: string;
	subtitle: string;
	description: string;
	icon: React.ElementType;
	iconColor: string;
	features: string[];
}

const BACKEND_CHOICES: BackendChoice[] = [
	{
		id: "vals",
		title: "AGE/SOPS Encryption",
		subtitle: "Local encryption keys",
		description:
			"Encrypt secrets with AGE keys and SOPS. Files are stored in your repo as encrypted YAML. Works fully offline.",
		icon: KeyRound,
		iconColor: "text-blue-500",
		features: [
			"Encrypted YAML files in your repo",
			"AGE public/private key pairs per developer",
			"Optional AWS KMS for team key management",
			"Works offline - no cloud dependency",
		],
	},
	{
		id: "chamber",
		title: "AWS Parameter Store",
		subtitle: "Chamber CLI + AWS SSM",
		description:
			"Store secrets in AWS SSM Parameter Store using the Chamber CLI. Requires AWS credentials and a KMS key.",
		icon: Server,
		iconColor: "text-amber-500",
		features: [
			"Centralized secrets in AWS SSM",
			"KMS encryption at rest",
			"IAM-based access control",
			"Requires AWS credentials locally",
		],
	},
];

export function SecretsBackendStep() {
	const {
		expandedStep,
		setExpandedStep,
		projectConfirmed,
		secretsBackend,
		isChamber,
	} = useSetupContext();

	const patchNixData = usePatchNixData();
	const [selected, setSelected] = useState<BackendOption | null>(null);
	const [saving, setSaving] = useState(false);

	// Use the current backend from context as the effective value
	const effectiveBackend = selected ?? secretsBackend;
	const isConfigured = secretsBackend === "vals" || secretsBackend === "chamber";

	const step: SetupStep = {
		id: "secrets-backend",
		title: "Secrets Backend",
		description: "Choose how secrets are stored and managed",
		status: isConfigured
			? "complete"
			: projectConfirmed
				? "incomplete"
				: "blocked",
		required: true,
		dependsOn: ["project-info"],
		icon: <Database className="h-5 w-5" />,
	};

	const handleSave = async () => {
		if (!effectiveBackend) return;
		setSaving(true);
		try {
			await patchNixData.mutateAsync({
				entity: "secrets",
				key: "",
				path: "backend",
				value: JSON.stringify(effectiveBackend),
				valueType: "string",
			});
			toast.success(
				effectiveBackend === "chamber"
					? "Backend set to AWS Parameter Store (Chamber)"
					: "Backend set to AGE/SOPS encryption",
			);
			// Navigate to next step based on choice
			if (effectiveBackend === "chamber") {
				// Chamber requires AWS infrastructure
				setExpandedStep("infrastructure");
			} else {
				// Vals flow: go to decryption key
				setExpandedStep("decryption-key");
			}
		} catch (err) {
			toast.error(
				err instanceof Error ? err.message : "Failed to save backend",
			);
		} finally {
			setSaving(false);
		}
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "secrets-backend"}
			onToggle={() =>
				setExpandedStep(
					expandedStep === "secrets-backend" ? null : "secrets-backend",
				)
			}
		>
			<div className="space-y-6">
				<p className="text-sm text-muted-foreground">
					Choose how your project stores and retrieves secrets. This controls
					encryption, entrypoint injection, and what the UI shows.
				</p>

				{/* Backend cards */}
				<div className="grid gap-4 sm:grid-cols-2">
					{BACKEND_CHOICES.map((choice) => {
						const Icon = choice.icon;
						const isSelected = effectiveBackend === choice.id;
						return (
							<button
								key={choice.id}
								type="button"
								onClick={() => setSelected(choice.id)}
								className={cn(
									"rounded-lg border p-4 text-left transition-all",
									"hover:border-primary/50 hover:bg-muted/30",
									isSelected &&
										"border-primary bg-primary/5 ring-1 ring-primary/30",
								)}
							>
								<div className="flex items-center gap-3 mb-2">
									<div
										className={cn(
											"flex h-10 w-10 items-center justify-center rounded-lg",
											isSelected ? "bg-primary/10" : "bg-muted",
										)}
									>
										<Icon
											className={cn(
												"h-5 w-5",
												isSelected ? "text-primary" : choice.iconColor,
											)}
										/>
									</div>
									<div>
										<h4 className="font-medium text-sm">{choice.title}</h4>
										<p className="text-xs text-muted-foreground">
											{choice.subtitle}
										</p>
									</div>
								</div>
								<p className="text-xs text-muted-foreground mb-3">
									{choice.description}
								</p>
								<ul className="space-y-1">
									{choice.features.map((feature) => (
										<li
											key={feature}
											className="text-xs text-muted-foreground flex items-start gap-1.5"
										>
											<span className="text-muted-foreground/60 mt-0.5">
												-
											</span>
											{feature}
										</li>
									))}
								</ul>
							</button>
						);
					})}
				</div>

				{/* Save button */}
				{effectiveBackend && (
					<div className="flex items-center gap-3">
						<Button
							onClick={handleSave}
							disabled={saving || (!selected && isConfigured)}
						>
							{saving ? (
								<Loader2 className="h-4 w-4 animate-spin mr-2" />
							) : (
								<Database className="h-4 w-4 mr-2" />
							)}
							{isConfigured && !selected ? "Already Configured" : "Save & Continue"}
						</Button>
						{isConfigured && !selected && (
							<span className="text-xs text-muted-foreground">
								Select a different backend to change
							</span>
						)}
					</div>
				)}

				{/* Success banner */}
				{isConfigured && !selected && (
					<div className="rounded-lg bg-emerald-700/10 border border-emerald-500/20 p-3">
						<p className="text-sm text-emerald-700 dark:text-emerald-200 flex items-center gap-2">
							<CheckCircle2 className="h-4 w-4" />
							{isChamber
								? "Using AWS Parameter Store (Chamber) for secrets"
								: "Using AGE/SOPS encryption for secrets"}
						</p>
					</div>
				)}
			</div>
		</StepCard>
	);
}
