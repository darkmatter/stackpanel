"use client";

import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Check, CheckCircle2, Cloud, Key, Loader2 } from "lucide-react";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function DecryptionKeyStep() {
	const {
		expandedStep,
		setExpandedStep,
		projectConfirmed,
		hasAwsKms,
		identityInfo,
		identityInput,
		setIdentityInput,
		handleSaveIdentity,
		isSaving,
	} = useSetupContext();

	const step: SetupStep = {
		id: "decryption-key",
		title: "Local Decryption Key",
		description: hasAwsKms
			? "Configure a local key for offline access"
			: "Configure your private key for decrypting secrets locally",
		status: identityInfo?.type
			? "complete"
			: hasAwsKms
				? "incomplete"
				: projectConfirmed
					? "incomplete"
					: "blocked",
		required: true,
		dependsOn: ["project-info"],
		icon: <Key className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "decryption-key"}
			onToggle={() =>
				setExpandedStep(
					expandedStep === "decryption-key" ? null : "decryption-key",
				)
			}
		>
			<div className="space-y-4">
				{hasAwsKms && (
					<div className="rounded-lg border border-blue-500/20 bg-blue-500/10 p-3">
						<p className="text-sm text-blue-700 dark:text-blue-300 flex items-center gap-2">
							<Cloud className="h-4 w-4" />
							You've configured AWS KMS — SOPS can use that to decrypt secrets
							in CI/CD. It is still recommended to configure a local key for
							offline or local development access.
						</p>
					</div>
				)}
				<p className="text-sm text-muted-foreground">
					Your decryption key allows you to decrypt secrets on this machine.
					This can be an AGE key or an SSH private key. To use AGE, run the
					following command to generate a key:{" "}
					<code className="bg-muted/30 p-1 rounded-md">
						age-keygen -o ~/.config/age/key.txt
					</code>
				</p>

				<div className="space-y-2">
					<Label>Private Key Path or Content</Label>
					<Input
						value={identityInput}
						onChange={(e) => setIdentityInput(e.target.value)}
						placeholder="~/.ssh/id_ed25519 or paste AGE key"
						className="font-mono"
					/>
					<p className="text-xs text-muted-foreground">
						Common paths: <code>~/.ssh/id_ed25519</code>,{" "}
						<code>~/.config/age/key.txt</code>
					</p>
				</div>

				<div className="flex gap-2">
					<Button
						onClick={handleSaveIdentity}
						disabled={isSaving || !identityInput}
					>
						{isSaving ? (
							<Loader2 className="h-4 w-4 animate-spin mr-2" />
						) : (
							<Check className="h-4 w-4 mr-2" />
						)}
						Save Identity
					</Button>
				</div>

				{identityInfo?.type && (
					<div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3">
						<p className="text-sm text-emerald-700 dark:text-emerald-300 flex items-center gap-2">
							<CheckCircle2 className="h-4 w-4" />
							{identityInfo.type === "ssh"
								? "SSH key configured"
								: "AGE key configured"}
						</p>
						{identityInfo.publicKey && (
							<code className="text-xs font-mono block mt-2 break-all text-muted-foreground">
								{identityInfo.publicKey}
							</code>
						)}
					</div>
				)}
			</div>
		</StepCard>
	);
}
