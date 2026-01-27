"use client";

import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Textarea } from "@ui/textarea";
import { Loader2, Plus } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useVariablesBackend } from "@/lib/use-agent";
import type { Variable } from "@/lib/types";
import { isSopsReference, isEncryptedKeyGroup, getKeyGroup } from "./constants";

interface AddVariableDialogProps {
	onSuccess: () => void;
}

/**
 * Dialog to add a new variable.
 * 
 * With the simplified schema:
 * - id: Path-based identifier like /dev/DATABASE_URL or /var/LOG_LEVEL
 * - value: Literal string or vals reference (ref+sops://...)
 * 
 * For vals backend, secrets use ref+sops:// format pointing to the SOPS file.
 * For chamber backend, secrets are plain values in encrypted keygroups (/dev/, /staging/, /prod/).
 */
export function AddVariableDialog({ onSuccess }: AddVariableDialogProps) {
	const { token } = useAgentContext();
	const agentClient = useAgentClient();
	const { data: backendData } = useVariablesBackend();
	const isChamber = backendData?.backend === "chamber";
	const [dialogOpen, setDialogOpen] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	
	// Form state
	const [varId, setVarId] = useState("");
	const [varValue, setVarValue] = useState("");

	const handleOpenChange = (open: boolean) => {
		setDialogOpen(open);
		if (!open) {
			// Reset form when closing
			setVarId("");
			setVarValue("");
		}
	};

	const handleSubmit = async () => {
		if (!token) {
			toast.error("Not connected to agent");
			return;
		}

		// Validate required fields
		const trimmedId = varId.trim();
		const trimmedValue = varValue.trim();

		if (!trimmedId) {
			toast.error("Please enter a variable ID");
			return;
		}

		if (!trimmedValue) {
			toast.error("Please enter a variable value");
			return;
		}

		// Ensure ID starts with /
		const normalizedId = trimmedId.startsWith("/") ? trimmedId : `/${trimmedId}`;

		setIsSaving(true);
		try {
			const client = agentClient;
			if (token) client.setToken(token);
			const variablesClient = client.nix.mapEntity<Variable>("variables");

			const existing = await variablesClient.get(normalizedId);
			if (existing) {
				toast.error(`Variable "${normalizedId}" already exists`);
				setIsSaving(false);
				return;
			}

			// With simplified schema, Variable just has id and value
			const newVariable: Variable = {
				id: normalizedId,
				value: trimmedValue,
			};

			await variablesClient.set(normalizedId, newVariable);
			
			const isSecret = isChamber
				? isEncryptedKeyGroup(getKeyGroup(normalizedId))
				: isSopsReference(trimmedValue);
			toast.success(`Created ${isSecret ? "secret" : "variable"} "${normalizedId}"`);

			handleOpenChange(false);
			onSuccess();
		} catch (err) {
			console.error("[AddVariable] Error:", err);
			toast.error(
				err instanceof Error ? err.message : "Failed to create variable",
			);
		} finally {
			setIsSaving(false);
		}
	};

	return (
		<Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
			<button
				type="button"
				onClick={() => setDialogOpen(true)}
				disabled={!token}
				className="flex items-center gap-2 px-3 py-1.5 rounded-md border border-dashed border-border bg-background text-xs hover:border-blue-500/50 hover:bg-blue-500/5 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
			>
				<Plus className="h-3 w-3 text-blue-500" />
				<span className="font-medium">Add Variable</span>
			</button>
			<DialogContent className="sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Add New Variable</DialogTitle>
					<DialogDescription>
						Create a new environment variable. Use /dev/, /prod/, or /var/ prefixes.
					</DialogDescription>
				</DialogHeader>
				<div className="py-4 space-y-4">
					<div className="space-y-2">
						<Label htmlFor="var-id">Variable ID *</Label>
						<Input
							id="var-id"
							value={varId}
							onChange={(e) => setVarId(e.target.value)}
							placeholder="/dev/DATABASE_URL or /var/LOG_LEVEL"
							className="font-mono"
						/>
						<p className="text-xs text-muted-foreground">
							Path-based ID. Keygroups: /var/ (plaintext), /dev/, /staging/, /prod/ (secrets)
						</p>
					</div>
					<div className="space-y-2">
						<Label htmlFor="var-value">Value *</Label>
						<Textarea
							id="var-value"
							value={varValue}
							onChange={(e) => setVarValue(e.target.value)}
							placeholder={isChamber ? "Secret value (stored in AWS SSM)" : "literal value or ref+sops://..."}
							className="font-mono min-h-[80px]"
						/>
						<p className="text-xs text-muted-foreground">
							{isChamber
								? "Plain value. Secrets in /dev/, /staging/, /prod/ keygroups are encrypted via AWS KMS."
								: "Literal value or vals reference (e.g., ref+sops://.stackpanel/secrets/dev.yaml#/KEY)"}
						</p>
					</div>
				</div>
				<DialogFooter>
					<Button variant="outline" onClick={() => handleOpenChange(false)}>
						Cancel
					</Button>
					<Button
						onClick={handleSubmit}
						disabled={isSaving || !varId.trim() || !varValue.trim()}
						className="bg-accent text-accent-foreground hover:bg-accent/90"
					>
						{isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
						Add Variable
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
