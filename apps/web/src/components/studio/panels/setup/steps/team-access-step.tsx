"use client";

import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
	CheckCircle2,
	Loader2,
	Plus,
	Trash2,
	Users,
	XCircle,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import {
	useRecipients,
	useAddRecipient,
	useRemoveRecipient,
	useRekeyWorkflowStatus,
} from "@/lib/use-agent";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function TeamAccessStep() {
	const { expandedStep, setExpandedStep, isChamber, goToStep } =
		useSetupContext();

	const { data: recipients, isLoading: recipientsLoading } = useRecipients();
	const { data: workflowStatus } = useRekeyWorkflowStatus();
	const addRecipient = useAddRecipient();
	const removeRecipient = useRemoveRecipient();

	const [newName, setNewName] = useState("");
	const [newKey, setNewKey] = useState("");
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

		if (!trimmedName || !trimmedKey) {
			toast.error("Name and public key are required");
			return;
		}

		try {
			await addRecipient.mutateAsync(
				keyType === "ssh"
					? { name: trimmedName, sshPublicKey: trimmedKey }
					: { name: trimmedName, publicKey: trimmedKey },
			);
			toast.success(`Added recipient "${trimmedName}"`);
			setNewName("");
			setNewKey("");
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
					secrets. Keys are stored in the recipients directory and committed
					to git.
				</p>

				{/* Self-service flow explanation */}
				<div className="rounded-lg border p-4 space-y-3">
					<h4 className="font-medium text-sm">Self-service onboarding:</h4>
					<ol className="list-decimal list-inside space-y-1.5 text-sm text-muted-foreground">
						<li>New team member enters the devshell — local key is auto-generated</li>
						<li>Their public key is registered in the recipients directory</li>
						<li>They push — GitHub Actions re-encrypts secrets for all recipients</li>
						<li>They pull — secrets are now accessible</li>
					</ol>
				</div>

				{/* Rekey workflow status */}
				{workflowStatus && (
					<div className="rounded-lg border p-3 flex items-center gap-2">
						{workflowStatus.exists ? (
							<>
								<CheckCircle2 className="h-4 w-4 text-emerald-500" />
								<span className="text-sm">
									Rekey workflow is configured
								</span>
							</>
						) : (
							<>
								<XCircle className="h-4 w-4 text-amber-500" />
								<span className="text-sm text-muted-foreground">
									Rekey workflow not found. Run{" "}
									<code>secrets:init-group</code> to generate it.
								</span>
							</>
						)}
					</div>
				)}

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
							No recipients yet. Enter the devshell to auto-register your key,
							or add team members below.
						</p>
					) : (
						<div className="space-y-2">
							{recipientList.map((r) => (
								<div
									key={r.name}
									className="flex items-center justify-between rounded-lg border px-3 py-2"
								>
									<div>
										<p className="text-sm font-medium">{r.name}</p>
										<p className="text-xs text-muted-foreground font-mono">
											{r.publicKey.slice(0, 32)}...
										</p>
									</div>
									<Button
										variant="ghost"
										size="sm"
										onClick={() => handleRemove(r.name)}
										disabled={removeRecipient.isPending}
									>
										<Trash2 className="h-3.5 w-3.5 text-muted-foreground" />
									</Button>
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
