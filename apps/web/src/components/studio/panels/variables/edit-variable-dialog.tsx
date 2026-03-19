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
import { Label } from "@ui/label";
import { Textarea } from "@ui/textarea";
import { Loader2, Pencil, Trash2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useVariablesBackend } from "@/lib/use-agent";
import { isEncryptedKeyGroup, getKeyGroup } from "./constants";

interface EditVariableDialogProps {
	variable: {
		id: string;
		value: string;
	};
	onSuccess: () => void;
	trigger?: React.ReactNode;
}

/**
 * Dialog to edit an existing variable.
 *
 * With the simplified schema, Variable has only id and value.
 * Type (secret/config/computed) is derived from the id path and value pattern.
 */
export function EditVariableDialog({
	variable,
	onSuccess,
	trigger,
}: EditVariableDialogProps) {
	const { token } = useAgentContext();
	const agentClient = useAgentClient();
	const { data: backendData } = useVariablesBackend();
	const isChamber = backendData?.backend === "chamber";
	const [dialogOpen, setDialogOpen] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	const [isDeleting, setIsDeleting] = useState(false);

	// Form state — id is read-only, only value can be edited
	const [varValue, setVarValue] = useState(variable.value);

	const handleOpenChange = (open: boolean) => {
		setDialogOpen(open);
		if (!open) {
			// Reset to current value when closing
			setVarValue(variable.value);
		}
	};

	const handleSubmit = async () => {
		if (!token) {
			toast.error("Not connected to agent");
			return;
		}

		const trimmedValue = varValue.trim();
		if (!trimmedValue) {
			toast.error("Please enter a variable value");
			return;
		}

		setIsSaving(true);
		try {
			const client = agentClient;
			if (token) client.setToken(token);
			const variablesClient = client.nix.mapEntity<{ value: string }>("variables");

			const updatedVariable = {
				value: trimmedValue,
			};

			await variablesClient.set(variable.id, updatedVariable);

			const isSecret = isEncryptedKeyGroup(getKeyGroup(variable.id));
			toast.success(`Updated ${isSecret ? "secret" : "variable"} "${variable.id}"`);

			handleOpenChange(false);
			onSuccess();
		} catch (err) {
			console.error("[EditVariable] Error:", err);
			toast.error(
				err instanceof Error ? err.message : "Failed to update variable",
			);
		} finally {
			setIsSaving(false);
		}
	};

	const handleDelete = async () => {
		if (!token) {
			toast.error("Not connected to agent");
			return;
		}

		if (!confirm(`Are you sure you want to delete "${variable.id}"?`)) {
			return;
		}

		setIsDeleting(true);
		try {
			const client = agentClient;
			if (token) client.setToken(token);
			const variablesClient = client.nix.mapEntity<{ value: string }>("variables");

			await variablesClient.remove(variable.id);
			toast.success(`Deleted variable "${variable.id}"`);
			handleOpenChange(false);
			onSuccess();
		} catch (err) {
			console.error("[EditVariable] Delete error:", err);
			toast.error(
				err instanceof Error ? err.message : "Failed to delete variable",
			);
		} finally {
			setIsDeleting(false);
		}
	};

	return (
		<Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
			{trigger ? (
				<div onClick={() => setDialogOpen(true)}>{trigger}</div>
			) : (
				<Button
					variant="ghost"
					size="sm"
					onClick={() => setDialogOpen(true)}
					disabled={!token}
					className="h-7 px-2 text-xs"
				>
					<Pencil className="h-3 w-3 mr-1" />
					Edit
				</Button>
			)}
			<DialogContent className="sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Edit Variable</DialogTitle>
					<DialogDescription>
						Update the variable value. The variable ID cannot be changed.
					</DialogDescription>
				</DialogHeader>
				<div className="py-4 space-y-4">
					<div className="p-3 rounded-lg bg-muted/50 border border-border">
						<Label className="text-xs text-muted-foreground font-medium">
							Variable ID
						</Label>
						<p className="font-mono text-sm mt-1">{variable.id}</p>
					</div>
					<div className="space-y-2">
						<Label htmlFor="edit-var-value">Value *</Label>
						<Textarea
							id="edit-var-value"
							value={varValue}
							onChange={(e) => setVarValue(e.target.value)}
							placeholder={isChamber ? "Value (stored in AWS SSM)" : "Literal value or vals reference"}
							className="font-mono min-h-[80px]"
							autoFocus
						/>
						<p className="text-xs text-muted-foreground">
						{isChamber
							? "Plain value. Encryption is handled by AWS KMS."
							: "Literal value. Secret values are managed via the Edit Secret dialog."}
						</p>
					</div>
				</div>
				<DialogFooter className="flex justify-between sm:justify-between">
					<Button
						variant="destructive"
						onClick={handleDelete}
						disabled={isDeleting || isSaving}
						className="gap-1"
					>
						{isDeleting && <Loader2 className="h-4 w-4 animate-spin" />}
						<Trash2 className="h-4 w-4" />
						Delete
					</Button>
					<div className="flex gap-2">
						<Button variant="outline" onClick={() => handleOpenChange(false)}>
							Cancel
						</Button>
						<Button
							onClick={handleSubmit}
							disabled={isSaving || isDeleting || !varValue.trim()}
							className="bg-accent text-accent-foreground hover:bg-accent/90"
						>
							{isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
							Save Changes
						</Button>
					</div>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
