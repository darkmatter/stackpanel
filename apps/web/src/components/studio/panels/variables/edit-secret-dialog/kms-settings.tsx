/**
 * Settings component for configuring AWS KMS encryption.
 * Writes to `stackpanel.secrets.kms` in config.nix via the secrets entity.
 * The state file fallback at `.stack/state/kms-config.json` is still read by
 * Nix for backward compatibility but is no longer the primary write target.
 */
"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { AlertCircle, Cloud, Loader2 } from "lucide-react";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { useNixEntityData } from "@/lib/use-agent";
import type { SecretsConfigEntity } from "@/lib/types";

export function KMSSettings() {
	const { data: secretsConfig, set, isLoading } = useNixEntityData<SecretsConfigEntity>("secrets");

	const [enabled, setEnabled] = useState(false);
	const [keyArn, setKeyArn] = useState("");
	const [awsProfile, setAwsProfile] = useState("");
	const [roleArn, setRoleArn] = useState("");
	const [isSaving, setIsSaving] = useState(false);
	const [error, setError] = useState<string | null>(null);

	useEffect(() => {
		const kms = (secretsConfig?.kms ?? {}) as {
			"key-arn"?: string;
			"aws-profile"?: string;
			"aws-role-arn"?: string;
		};
		const arn = kms["key-arn"] ?? "";
		setEnabled(arn !== "");
		setKeyArn(arn);
		setAwsProfile(kms["aws-profile"] ?? "");
		setRoleArn(kms["aws-role-arn"] ?? "");
	}, [secretsConfig]);

	const handleSave = async () => {
		if (enabled && keyArn && !keyArn.startsWith("arn:aws:kms:")) {
			setError("Invalid KMS ARN format — must start with arn:aws:kms:");
			return;
		}

		setIsSaving(true);
		setError(null);
		try {
			const next: SecretsConfigEntity = {
				...secretsConfig,
				kms: {
					"key-arn": enabled ? keyArn : "",
					...(awsProfile ? { "aws-profile": awsProfile } : {}),
					...(roleArn ? { "aws-role-arn": roleArn } : {}),
				},
			};
			await set(next);
			toast.success(enabled ? "KMS ARN saved to config.nix — reload shell to regenerate .sops.yaml" : "KMS ARN cleared");
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
		setRoleArn("");
		setIsSaving(true);
		try {
			const next: SecretsConfigEntity = {
				...secretsConfig,
				kms: { "key-arn": "" },
			};
			await set(next);
			toast.success("KMS disabled");
		} catch {
			toast.error("Failed to disable KMS");
		} finally {
			setIsSaving(false);
		}
	};

	return (
		<div className="rounded-lg border border-border p-4 space-y-3">
			<div className="flex items-center justify-between">
				<div className="flex items-center gap-2">
					<Cloud className="h-4 w-4 text-muted-foreground" />
					<span className="text-sm font-medium">AWS KMS</span>
					{enabled && keyArn && (
						<span className="text-xs px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-600">
							Enabled
						</span>
					)}
				</div>
				<Switch checked={enabled} onCheckedChange={setEnabled} disabled={isLoading} />
			</div>

			<p className="text-xs text-muted-foreground">
				Add an AWS KMS key as an additional SOPS recipient. The ARN is stored in
				<code> config.nix</code> under <code>stackpanel.secrets.kms</code> and
				rendered into <code>.stack/secrets/.sops.yaml</code> on the next shell entry.
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
							placeholder="arn:aws:kms:us-east-1:123456789012:key/mrk-..."
							className="font-mono text-xs"
							disabled={isLoading}
						/>
					</div>

					<div className="space-y-1.5">
						<Label className="text-xs">AWS Profile (optional)</Label>
						<Input
							value={awsProfile}
							onChange={(e) => setAwsProfile(e.target.value)}
							placeholder="default"
							className="font-mono text-xs"
							disabled={isLoading}
						/>
					</div>

					<div className="space-y-1.5">
						<Label className="text-xs">IAM Role ARN for assume-role (optional)</Label>
						<Input
							value={roleArn}
							onChange={(e) => setRoleArn(e.target.value)}
							placeholder="arn:aws:iam::123456789012:role/sops-decryptor"
							className="font-mono text-xs"
							disabled={isLoading}
						/>
					</div>

					<div className="flex gap-2 pt-1">
						<Button variant="outline" size="sm" onClick={handleSave} disabled={isSaving || isLoading}>
							{isSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}
						</Button>
						<Button variant="ghost" size="sm" onClick={handleDisable} disabled={isSaving}>
							Disable
						</Button>
					</div>
				</div>
			)}

			{!enabled && (
				<p className="text-[11px] text-muted-foreground/70">
					Enable to add a KMS ARN to every SOPS creation rule.
				</p>
			)}
		</div>
	);
}
