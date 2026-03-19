"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, CheckCircle2, KeyRound, Loader2, Save } from "lucide-react";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { toast } from "sonner";
import { useSopsAgeKeysStatus, useNixEntityData } from "@/lib/use-agent";
import type { SecretsConfigEntity } from "@/lib/types";
import { MultiValueCombobox } from "../../variables/multi-value-combobox";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function SopsAgeKeysStep() {
	const { expandedStep, setExpandedStep, isChamber, goToStep } = useSetupContext();
	const { data: status, isLoading, refetch } = useSopsAgeKeysStatus();
	const { data: secretsConfig, set } = useNixEntityData<SecretsConfigEntity>("secrets");
	const [userKeyPath, setUserKeyPath] = useState("");
	const [repoKeyPath, setRepoKeyPath] = useState("");
	const [paths, setPaths] = useState<string[]>([]);
	const [opRefs, setOpRefs] = useState<string[]>([]);

	useEffect(() => {
		const sopsAgeKeys = (secretsConfig?.["sops-age-keys"] ?? {}) as {
			"user-key-path"?: string;
			"repo-key-path"?: string;
			paths?: string[];
			"op-refs"?: string[];
		};
		setUserKeyPath(sopsAgeKeys["user-key-path"] ?? status?.userKeyPath ?? "");
		setRepoKeyPath(sopsAgeKeys["repo-key-path"] ?? status?.repoKeyPath ?? ".stack/keys/local.txt");
		setPaths(sopsAgeKeys.paths ?? []);
		setOpRefs(sopsAgeKeys["op-refs"] ?? []);
	}, [secretsConfig, status?.repoKeyPath, status?.userKeyPath]);

	const step: SetupStep = {
		id: "sops-age-keys",
		title: "Decryption Keys",
		description: "Make sure sops-age-keys returns a key whose public key matches a configured recipient",
		status: isChamber ? "complete" : status?.available && status?.recipientMatch ? "complete" : "incomplete",
		required: !isChamber,
		icon: <KeyRound className="h-5 w-5" />,
	};

	const knownPathOptions = useMemo(
		() => [status?.userKeyPath, status?.repoKeyPath, status?.localKeyPath, "~/.config/age/key.txt", "~/.ssh/id_ed25519"].filter((v): v is string => Boolean(v)),
		[status?.localKeyPath, status?.repoKeyPath, status?.userKeyPath],
	);

	const handleSave = async () => {
		const next: SecretsConfigEntity = {
			...(secretsConfig ?? {}),
			"sops-age-keys": {
				"user-key-path": userKeyPath,
				"repo-key-path": repoKeyPath,
				paths,
				"op-refs": opRefs,
			},
		};
		await set(next);
		toast.success("SOPS age key sources updated");
		await refetch();
	};

	const handleRecheck = async () => {
		const result = await refetch();
		const data = result.data;
		if (!data) {
			toast.error("Re-check failed", { description: "No status response returned." });
			return;
		}
		if (data.available && data.recipientMatch) {
			toast.success("sops-age-keys is ready", {
				description: `Resolved ${data.keyCount} key(s) and matched a configured recipient.`,
			});
			return;
		}
		toast.error("sops-age-keys needs attention", {
			description:
				data.recommendation ||
				(data.available
					? `Resolved ${data.keyCount} key(s), but none matched a configured recipient.`
					: "No AGE key is currently resolvable."),
		});
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "sops-age-keys"}
			onToggle={() => setExpandedStep(expandedStep === "sops-age-keys" ? null : "sops-age-keys")}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					This step checks the actual <code>sops-age-keys</code> command used by Stackpanel. It should return at least one
					 <code>AGE-SECRET-KEY-...</code> line before you start editing secrets.
				</p>

				<div className="rounded-lg border p-4 space-y-2">
					<div className="flex items-center justify-between">
						<div className="flex items-center gap-2">
							<KeyRound className="h-4 w-4 text-muted-foreground" />
							<span className="text-sm font-medium">sops-age-keys status</span>
						</div>
						{isLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : status?.available ? <CheckCircle2 className="h-4 w-4 text-green-500" /> : <AlertTriangle className="h-4 w-4 text-amber-500" />}
					</div>
					<p className="text-xs text-muted-foreground">
						{status?.available
							? status?.recipientMatch
								? `Resolved ${status.keyCount} key(s); at least one matches a configured recipient.`
								: `Resolved ${status.keyCount} key(s), but none match a configured recipient.`
							: "No AGE key is currently resolvable."}
					</p>
					{status?.publicKeys?.length ? (
						<div className="space-y-1">
							<p className="text-xs font-medium text-muted-foreground">Derived public keys</p>
							<div className="space-y-1">
								{status.publicKeys.map((key) => (
									<p key={key} className="text-[11px] font-mono text-muted-foreground break-all">{key}</p>
								))}
							</div>
						</div>
					) : null}
					{status?.recommendation ? (
						<div className="rounded-md border border-amber-500/30 bg-amber-500/5 p-3 text-sm text-muted-foreground flex items-start gap-2">
							<AlertTriangle className="h-4 w-4 text-amber-500 mt-0.5" />
							<div>{status.recommendation}</div>
						</div>
					) : null}
					{status?.error ? <p className="text-xs text-destructive whitespace-pre-wrap">{status.error}</p> : null}
				</div>

				<div className="rounded-lg border p-4 space-y-3">
					<h4 className="font-medium text-sm">Configure key sources</h4>
					<div className="space-y-1.5">
						<Label>User key path</Label>
						<Input value={userKeyPath} onChange={(e) => setUserKeyPath(e.target.value)} placeholder={status?.userKeyPath || "$XDG_CONFIG_HOME/sops/age/keys.txt"} className="font-mono text-sm" />
						<p className="text-xs text-muted-foreground">Preferred user-managed key path outside the repo. On macOS, `$HOME/Library/Application Support/sops/age/keys.txt` is a good default. Elsewhere, SOPS defaults to `$XDG_CONFIG_HOME/sops/age/keys.txt`.</p>
					</div>
					<div className="space-y-1.5">
						<Label>Repo key path</Label>
						<Input value={repoKeyPath} onChange={(e) => setRepoKeyPath(e.target.value)} placeholder=".stack/keys/local.txt" className="font-mono text-sm" />
						<p className="text-xs text-muted-foreground">Stackpanel's repo-local fallback for development. This is convenient, but less robust than a user or external key source.</p>
					</div>
					<div className="space-y-1.5">
						<Label>Additional file paths</Label>
						<MultiValueCombobox value={paths} onChange={setPaths} options={knownPathOptions} allowCreate placeholder="Add key file paths..." />
						<p className="text-xs text-muted-foreground">Optional extra paths checked after the user and repo key paths.</p>
					</div>
					<div className="space-y-1.5">
						<Label>1Password refs</Label>
						<MultiValueCombobox value={opRefs} onChange={setOpRefs} options={[]} allowCreate placeholder="op://vault/item/field" />
						<p className="text-xs text-muted-foreground">Recommended for team-shared storage outside the repo. You can also use another secure external system such as macOS Keychain or AWS SSM via your own helper path.</p>
					</div>
					<div className="flex items-center gap-2">
						<Button size="sm" onClick={handleSave}><Save className="mr-1 h-3.5 w-3.5" />Save sources</Button>
						<Button variant="outline" size="sm" onClick={handleRecheck}>Re-check</Button>
					</div>
				</div>

				{status?.available && status?.recipientMatch ? (
					<Button variant="outline" onClick={() => goToStep("init-groups")}>Continue to SOPS Rules</Button>
				) : null}
			</div>
		</StepCard>
	);
}
