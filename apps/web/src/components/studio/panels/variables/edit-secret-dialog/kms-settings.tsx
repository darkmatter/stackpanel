/**
 * Settings component for configuring AWS KMS encryption.
 * Can be used standalone in the variables panel.
 * Stores the config in .stackpanel/state/ (gitignored).
 */
"use client";

import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { AlertCircle, Cloud, Loader2 } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import type { KMSConfigResponse } from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";

export function KMSSettings() {
	const { token } = useAgentContext();
	const agentClient = useAgentClient();
	const [kmsConfig, setKmsConfig] = useState<KMSConfigResponse | null>(null);
	const [enabled, setEnabled] = useState(false);
	const [keyArn, setKeyArn] = useState("");
	const [awsProfile, setAwsProfile] = useState("");
	const [isLoading, setIsLoading] = useState(true);
	const [isSaving, setIsSaving] = useState(false);
	const [error, setError] = useState<string | null>(null);

	// Load current config on mount
	useEffect(() => {
		if (!token) return;
		const loadConfig = async () => {
			try {
				const client = agentClient;
				const config = await client.getKMSConfig();
				setKmsConfig(config);
				setEnabled(config.enable);
				setKeyArn(config.keyArn);
				setAwsProfile(config.awsProfile);
			} catch (err) {
				console.warn("Failed to load KMS config:", err);
			} finally {
				setIsLoading(false);
			}
		};
		loadConfig();
	}, [token]);

	const handleSave = async () => {
		if (!token) return;

		// Validate ARN if enabling
		if (enabled && keyArn && !keyArn.startsWith("arn:aws:kms:")) {
			setError("Invalid KMS ARN format - must start with arn:aws:kms:");
			return;
		}

		setIsSaving(true);
		setError(null);
		try {
			const client = agentClient;
			const result = await client.setKMSConfig({
				enable: enabled,
				keyArn: keyArn,
				awsProfile: awsProfile || undefined,
			});
			setKmsConfig(result);
			toast.success(result.enable ? "KMS enabled" : "KMS disabled");
		} catch (err) {
			const msg = err instanceof Error ? err.message : "Failed to save";
			setError(msg);
			toast.error(msg);
		} finally {
			setIsSaving(false);
		}
	};

	const handleDisable = async () => {
		setEnabled(false);
		setKeyArn("");
		setAwsProfile("");
		if (!token) return;
		try {
			const client = agentClient;
			const result = await client.setKMSConfig({ enable: false, keyArn: "" });
			setKmsConfig(result);
			toast.success("KMS disabled");
		} catch (err) {
			toast.error("Failed to disable KMS");
		}
	};

	return (
		<div className="rounded-lg border border-border p-4 space-y-3">
			<div className="flex items-center justify-between">
				<div className="flex items-center gap-2">
					<Cloud className="h-4 w-4 text-muted-foreground" />
					<span className="text-sm font-medium">AWS KMS</span>
					{kmsConfig?.enable && (
						<span className="text-xs px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-600">
							Enabled
						</span>
					)}
				</div>
				<Switch
					checked={enabled}
					onCheckedChange={setEnabled}
					disabled={isLoading}
				/>
			</div>

			<p className="text-xs text-muted-foreground">
				Use AWS KMS for secret encryption. Works with AWS Roles Anywhere.
			</p>

			{enabled && (
				<div className="space-y-3 pt-2">
					{error && (
						<div className="flex items-center gap-2 text-xs text-destructive">
							<AlertCircle className="h-3 w-3" />
							{error}
						</div>
					)}

					<div className="space-y-1.5">
						<Label className="text-xs">KMS Key ARN</Label>
						<Input
							value={keyArn}
							onChange={(e) => setKeyArn(e.target.value)}
							placeholder="arn:aws:kms:us-east-1:123456789012:key/..."
							className="font-mono text-xs"
							disabled={isLoading}
						/>
					</div>

					<div className="space-y-1.5">
						<Label className="text-xs">AWS Profile (optional)</Label>
						<Input
							value={awsProfile}
							onChange={(e) => setAwsProfile(e.target.value)}
							placeholder="Leave empty for default credentials"
							className="font-mono text-xs"
							disabled={isLoading}
						/>
					</div>

					<div className="flex gap-2 pt-1">
						<Button
							variant="outline"
							size="sm"
							onClick={handleSave}
							disabled={isSaving || isLoading}
						>
							{isSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}
						</Button>
						{kmsConfig?.enable && (
							<Button
								variant="ghost"
								size="sm"
								onClick={handleDisable}
								disabled={isSaving}
							>
								Disable
							</Button>
						)}
					</div>
				</div>
			)}

			{!enabled && kmsConfig?.source === "" && (
				<p className="text-[11px] text-muted-foreground/70">
					Enable to add KMS encryption to your SOPS secrets. Run{" "}
					<code>generate-sops-config</code> after enabling.
				</p>
			)}
		</div>
	);
}
