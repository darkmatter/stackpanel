"use client";

import { Button } from "@ui/button";
import { Badge } from "@ui/badge";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
	Loader2,
	Plus,
	Trash2,
	Users,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import {
	useRecipients,
	useAddRecipient,
	useRemoveRecipient,
} from "@/lib/use-agent";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function TeamAccessStep() {
	const { expandedStep, setExpandedStep, isChamber, goToStep } =
		useSetupContext();

	const { data: recipients, isLoading: recipientsLoading } = useRecipients();
	const addRecipient = useAddRecipient();
	const removeRecipient = useRemoveRecipient();

	const [newName, setNewName] = useState("");
	const [newKey, setNewKey] = useState("");
	const [newTags, setNewTags] = useState("");
	const [keyType, setKeyType] = useState<"age" | "ssh">("age");

	const recipientList = recipients?.recipients ?? [];
	const hasRecipients = recipientList.length > 0;

	const step: SetupStep = {
		id: "team-access",
		title: "Team Access",
		description: "Manage who can decrypt secrets",
		status: isChamber
			? "complete"
			: hasRecipients
				? "complete"
				: "optional",
		required: false,
		icon: <Users className="h-5 w-5" />,
	};

	const handleAdd = async () => {
		const trimmedName = newName.trim();
		const trimmedKey = newKey.trim();
		const parsedTags = newTags
			.split(",")
			.map((tag) => tag.trim())
			.filter(Boolean);

		if (!trimmedName || !trimmedKey) {
			toast.error("Name and public key are required");
			return;
		}
		if (parsedTags.length === 0) {
			toast.error("Add at least one tag");
			return;
		}

		try {
			await addRecipient.mutateAsync(
				keyType === "ssh"
					? { name: trimmedName, sshPublicKey: trimmedKey, tags: parsedTags }
					: { name: trimmedName, publicKey: trimmedKey, tags: parsedTags },
			);
			toast.success(`Added recipient "${trimmedName}"`);
			setNewName("");
			setNewKey("");
			setNewTags("");
		} catch (err) {
			toast.error(
				err instanceof Error ? err.message : "Failed to add recipient",
			);
		}
	};

	const handleRemove = async (name: string) => {
		try {
			await removeRecipient.mutateAsync(name);
			toast.success(`Removed recipient "${name}"`);
		} catch (err) {
			toast.error(
				err instanceof Error ? err.message : "Failed to remove recipient",
			);
		}
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "team-access"}
			onToggle={() =>
				setExpandedStep(
					expandedStep === "team-access" ? null : "team-access",
				)
			}
		>
			<div className="space-y-4">
				<p className="text-sm text-muted-foreground">
					Manage AGE public keys for team members who need to decrypt
					secrets. Keys are configured in Nix and rendered into
					<code>.stack/secrets/.sops.yaml</code>.
				</p>
				<p className="text-xs text-muted-foreground">
					Recipients marked <code>users</code> come from <code>stackpanel.users</code> and are read-only here.
				</p>

				{/* Self-service flow explanation */}
				<div className="rounded-lg border p-4 space-y-3">
					<h4 className="font-medium text-sm">Self-service onboarding:</h4>
					<ol className="list-decimal list-inside space-y-1.5 text-sm text-muted-foreground">
						<li>New team member enters the devshell — local key is auto-generated</li>
						<li>They add their public key and tags in the UI or Nix config</li>
						<li>An existing recipient runs <code>.stack/secrets/bin/rekey.sh</code></li>
						<li>They pull the updated <code>vars/*.sops.yaml</code> files</li>
					</ol>
				</div>

				{/* Current recipients */}
				<div>
					<h4 className="text-sm font-medium mb-2">
						Recipients ({recipientList.length})
					</h4>
					{recipientsLoading ? (
						<div className="flex items-center gap-2 py-2">
							<Loader2 className="h-4 w-4 animate-spin" />
							<span className="text-sm text-muted-foreground">Loading...</span>
						</div>
					) : recipientList.length === 0 ? (
						<p className="text-sm text-muted-foreground py-2">
							No recipients yet. Add them in Nix config, then re-enter the devshell.
						</p>
					) : (
						<div className="space-y-2">
							{recipientList.map((r) => (
								<div
									key={r.name}
									className="flex items-center justify-between rounded-lg border px-3 py-2"
								>
									<div>
										<div className="flex items-center gap-2 flex-wrap">
											<p className="text-sm font-medium">{r.name}</p>
											<Badge variant="outline">
												{r.source === "secrets" ? "config" : "users"}
											</Badge>
											{(r.tags ?? []).map((tag) => (
												<Badge key={`${r.name}-${tag}`} variant="secondary">
													{tag}
												</Badge>
											))}
										</div>
										<p className="text-xs text-muted-foreground font-mono">
											{r.publicKey.slice(0, 32)}...
										</p>
									</div>
									{r.canDelete ? (
										<Button
											variant="ghost"
											size="sm"
											onClick={() => handleRemove(r.name)}
											disabled={removeRecipient.isPending}
										>
											<Trash2 className="h-3.5 w-3.5 text-muted-foreground" />
										</Button>
									) : null}
								</div>
							))}
						</div>
					)}
				</div>

				{/* Add recipient form */}
				<div className="rounded-lg border p-4 space-y-3">
					<h4 className="font-medium text-sm">Add team member</h4>
					<div className="grid gap-3 sm:grid-cols-2">
						<div>
							<Label htmlFor="recipient-name" className="text-xs">
								Name
							</Label>
							<Input
								id="recipient-name"
								placeholder="e.g. alice"
								value={newName}
								onChange={(e) => setNewName(e.target.value)}
								className="mt-1"
							/>
						</div>
						<div>
							<Label htmlFor="key-type" className="text-xs">
								Key type
							</Label>
							<div className="flex gap-2 mt-1">
								<Button
									variant={keyType === "age" ? "default" : "outline"}
									size="sm"
									onClick={() => setKeyType("age")}
								>
									AGE
								</Button>
								<Button
									variant={keyType === "ssh" ? "default" : "outline"}
									size="sm"
									onClick={() => setKeyType("ssh")}
								>
									SSH
								</Button>
							</div>
						</div>
					</div>
					<div>
						<Label htmlFor="recipient-key" className="text-xs">
							{keyType === "ssh" ? "SSH public key" : "AGE public key"}
						</Label>
						<Input
							id="recipient-key"
							placeholder={
								keyType === "ssh"
									? "ssh-ed25519 AAAA..."
									: "age1..."
							}
							value={newKey}
							onChange={(e) => setNewKey(e.target.value)}
							className="mt-1 font-mono text-xs"
						/>
					</div>
					<div>
						<Label htmlFor="recipient-tags" className="text-xs">
							Tags
						</Label>
						<Input
							id="recipient-tags"
							placeholder="e.g. dev, prod, shared"
							value={newTags}
							onChange={(e) => setNewTags(e.target.value)}
							className="mt-1"
						/>
					</div>
					<Button
						size="sm"
						onClick={handleAdd}
						disabled={addRecipient.isPending || !newName.trim() || !newKey.trim()}
					>
						{addRecipient.isPending ? (
							<Loader2 className="h-3 w-3 animate-spin mr-1" />
						) : (
							<Plus className="h-3 w-3 mr-1" />
						)}
						Add Recipient
					</Button>
				</div>

				{hasRecipients && (
					<Button
						variant="outline"
						onClick={() => goToStep("verify-config")}
					>
						Continue to Verification
					</Button>
				)}
			</div>
		</StepCard>
	);
}
